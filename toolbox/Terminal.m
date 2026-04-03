% Copyright 2026 The MathWorks, Inc.

classdef Terminal < handle
    %TERMINAL Embeds a system terminal inside a MATLAB figure using uihtml.
    %
    %   t = Terminal()                    — docked terminal with default name
    %   t = Terminal(Name="Build")        — docked terminal with custom name
    %   t = Terminal(WindowStyle="normal") — undocked terminal in its own window
    %   t = Terminal(parent)              — terminal inside an existing figure/panel
    %   delete(t)                         — closes the terminal and kills the server
    %
    %   Name-Value Arguments:
    %     Name        - Title of the terminal window (default: "MATLAB Terminal")
    %     WindowStyle - "docked" (default) or "normal"
    %
    %   Static methods:
    %     Terminal.install()  — download the server binary for this platform
    %     Terminal.update()   — re-download the server binary
    %
    %   Examples:
    %     t = Terminal();
    %     t = Terminal(Name="Git", WindowStyle="normal");
    %     delete(t);

    properties (Access = private)
        ServerProcess   % struct with fields: pid (double), port (double)
        HTMLComponent   % uihtml handle
        AuthToken       % random hex auth string
        ParentFigure    % figure or uifigure handle
        ServerBinary    % absolute path to the Go binary
        PollTimer       % timer object for polling server output
        PollSeq         % last sequence number received from server
        BaseURL         % server base URL
        ReadOpts        % cached weboptions for webread
        WriteOpts       % cached weboptions for webwrite
        OutQueue cell = {}  % queued messages from JS to send to server
    end

    properties (Constant, Access = private)
        DEFAULT_IDLE_TIMEOUT = 30   % seconds
        SERVER_BINARY_NAME = 'matlab-terminal-server'
        POLL_INTERVAL = 0.1         % 100ms polling interval
    end

    methods
        function obj = Terminal(parent, options)
            %TERMINAL Construct a terminal instance.
            arguments
                parent = []
                options.Name (1,1) string = "MATLAB Terminal"
                options.WindowStyle (1,1) string {mustBeMember(options.WindowStyle, ["docked", "normal"])} = "docked"
            end

            % --- Parent container ---
            if isempty(parent)
                parent = uifigure('Name', options.Name, ...
                    'Position', [100 100 800 500], ...
                    'WindowStyle', options.WindowStyle);
            end
            obj.ParentFigure = parent;

            % --- Auth token (32-char hex string, no Java) ---
            obj.AuthToken = sprintf('%04x', randi(65535, 1, 8));

            % --- Extract bundled assets if needed ---
            Terminal.extractWebAssets();

            % --- Locate the server binary ---
            obj.ServerBinary = Terminal.findBinary();
            if isempty(obj.ServerBinary)
                error('Terminal:BinaryNotFound', ...
                    ['Server binary "%s" not found.\n' ...
                     'Run  Terminal.install()  to download it.'], ...
                    Terminal.SERVER_BINARY_NAME);
            end

            % --- Build environment info ---
            matlabPid = num2str(feature('getpid'));
            matlabRoot = matlabroot;

            % --- Start the server process ---
            cmd = sprintf('"%s" --token "%s" --env "MATLAB_PID=%s" --env "MATLAB_ROOT=%s"', ...
                obj.ServerBinary, obj.AuthToken, matlabPid, matlabRoot);

            tmpFile = [tempname, '.txt'];
            bgCmd = sprintf('%s > "%s" 2>&1 & echo $!', cmd, tmpFile);
            [status, pidStr] = system(bgCmd);
            if status ~= 0
                error('Terminal:ServerStartFailed', ...
                    'Failed to start server process: %s', pidStr);
            end
            serverPid = str2double(strtrim(pidStr));

            % Wait for the server to print its PORT line.
            port = [];
            maxWait = 5;
            elapsed = 0;
            while elapsed < maxWait
                pause(0.2);
                elapsed = elapsed + 0.2;
                if isfile(tmpFile)
                    raw = fileread(tmpFile);
                    tok = regexp(raw, 'PORT:(\d+)', 'tokens', 'once');
                    if ~isempty(tok)
                        port = str2double(tok{1});
                        break;
                    end
                end
            end

            if isfile(tmpFile)
                delete(tmpFile);
            end

            if isempty(port)
                system(sprintf('kill %d 2>/dev/null', serverPid));
                error('Terminal:NoPort', ...
                    'Server did not report a port within %d seconds.', maxWait);
            end

            obj.ServerProcess = struct('pid', serverPid, 'port', port);
            obj.BaseURL = sprintf('http://127.0.0.1:%d', port);
            obj.PollSeq = 0;

            % Pre-create weboptions to avoid re-parsing every call.
            obj.ReadOpts = weboptions('HeaderFields', {'Authorization', obj.AuthToken}, ...
                'Timeout', 2, 'ContentType', 'json');
            obj.WriteOpts = weboptions('HeaderFields', {'Authorization', obj.AuthToken}, ...
                'MediaType', 'application/json', 'Timeout', 2);

            % --- Read MATLAB theme / font settings ---
            themeConfig = Terminal.buildThemeConfig();

            % --- Locate web assets ---
            % extractWebAssets (called above) ensures these exist.
            htmlDir = fullfile(fileparts(mfilename('fullpath')), 'html');
            htmlFile = fullfile(htmlDir, 'index.html');
            if ~isfile(htmlFile)
                % Installed via .mltbx — use extracted cache.
                htmlDir = fullfile(prefdir, 'matlab-terminal', 'html');
                htmlFile = fullfile(htmlDir, 'index.html');
            end
            if ~isfile(htmlFile)
                error('Terminal:HTMLNotFound', ...
                    'Could not find index.html at:\n  %s', htmlFile);
            end

            if isprop(parent, 'AutoResizeChildren')
                parent.AutoResizeChildren = 'off';
            end

            obj.HTMLComponent = uihtml(parent);
            obj.HTMLComponent.Position = [0 0 parent.Position(3) parent.Position(4)];
            obj.HTMLComponent.HTMLSource = htmlFile;

            % Auto-resize.
            obj.ParentFigure.SizeChangedFcn = @(~,~) set(obj.HTMLComponent, ...
                'Position', [0 0 obj.ParentFigure.Position(3) obj.ParentFigure.Position(4)]);

            % Clean up when figure is closed.
            obj.ParentFigure.CloseRequestFcn = @(~,~) delete(obj);

            % Use a one-shot timer to initialize AFTER the constructor returns.
            % This prevents DataChangedFcn from firing during construction.
            initTimer = timer('StartDelay', 1.5, ...
                'TimerFcn', @(t,~) obj.deferredInit(t, themeConfig));
            start(initTimer);
        end

        function delete(obj)
            %DELETE Clean up: stop timer, kill server, close figure.
            if ~isempty(obj.PollTimer) && isvalid(obj.PollTimer)
                stop(obj.PollTimer);
                delete(obj.PollTimer);
            end
            if ~isempty(obj.ServerProcess) && isstruct(obj.ServerProcess) ...
                    && isfield(obj.ServerProcess, 'pid') && ~isnan(obj.ServerProcess.pid)
                system(sprintf('kill %d 2>/dev/null', obj.ServerProcess.pid));
            end
            if ~isempty(obj.ParentFigure) && isvalid(obj.ParentFigure)
                obj.ParentFigure.CloseRequestFcn = '';
                delete(obj.ParentFigure);
            end
        end
    end

    methods (Access = private)
        function deferredInit(obj, initTimer, themeConfig)
            %DEFERREDINIT Called after constructor returns to avoid reentrant callbacks.
            stop(initTimer);
            delete(initTimer);

            % Now it's safe to set up the data channel and callbacks.
            obj.HTMLComponent.DataChangedFcn = @(src, ~) obj.onJSMessage(src);

            % Send init config to JS.
            obj.HTMLComponent.Data = struct('type', 'init', 'theme', themeConfig);

            % Start polling for server output.
            obj.PollTimer = timer( ...
                'ExecutionMode', 'fixedSpacing', ...
                'Period', obj.POLL_INTERVAL, ...
                'TimerFcn', @(~,~) obj.pollOutput(), ...
                'ErrorFcn', @(~,~) []);
            start(obj.PollTimer);
        end

        function onJSMessage(obj, src)
            %ONJSMESSAGE Handle messages from JS via the Data channel.
            %   Queues messages for the poll timer to process, avoiding
            %   concurrent webread/webwrite calls.
            msg = src.Data;
            if ~isstruct(msg) || ~isfield(msg, 'type')
                return;
            end
            obj.OutQueue{end+1} = msg;
        end

        function pollOutput(obj)
            %POLLOUTPUT Process queued JS messages, then poll for output.
            try
                % --- Drain outbound queue (JS -> server) ---
                while ~isempty(obj.OutQueue)
                    msg = obj.OutQueue{1};
                    obj.OutQueue(1) = [];
                    obj.processJSMessage(msg);
                end

                % --- Poll for server output ---
                url = sprintf('%s/api/poll?since=%d', obj.BaseURL, obj.PollSeq);
                resp = webread(url, obj.ReadOpts);
                if isfield(resp, 'messages') && ~isempty(resp.messages)
                    msgs = resp.messages;
                    hasExited = false;
                    if iscell(msgs)
                        for i = 1:numel(msgs)
                            m = msgs{i};
                            if m.seq > obj.PollSeq
                                obj.PollSeq = m.seq;
                            end
                            if strcmp(m.type, 'exited')
                                hasExited = true;
                            end
                        end
                        obj.sendToJS(struct('type', 'batch', 'messages', {msgs}));
                    elseif isstruct(msgs)
                        for i = 1:numel(msgs)
                            if msgs(i).seq > obj.PollSeq
                                obj.PollSeq = msgs(i).seq;
                            end
                            if strcmp(msgs(i).type, 'exited')
                                hasExited = true;
                            end
                        end
                        obj.sendToJS(struct('type', 'batch', 'messages', {msgs}));
                    end
                    if hasExited
                        obj.checkAllExited();
                    end
                end
            catch
                % Ignore errors (server may be restarting or session gone).
            end
        end

        function processJSMessage(obj, msg)
            %PROCESSJSMESSAGE Execute a single queued JS message.
            switch msg.type
                case 'create'
                    resp = obj.serverPost('/api/create', struct('cols', 80, 'rows', 24));
                    if ~isempty(resp) && isfield(resp, 'id')
                        obj.sendToJS(struct('type', 'created', 'id', resp.id));
                    end
                case 'input'
                    obj.serverPost('/api/input', struct('id', msg.id, 'data', msg.data));
                case 'resize'
                    obj.serverPost('/api/resize', struct('id', msg.id, 'cols', msg.cols, 'rows', msg.rows));
                case 'close'
                    obj.serverPost('/api/close', struct('id', msg.id));
            end
        end

        function checkAllExited(obj)
            %CHECKALLEXITED Close window if server has no active sessions.
            try
                url = [obj.BaseURL, '/api/sessions'];
                resp = webread(url, obj.ReadOpts);
                if resp.count > 0
                    return;  % Other sessions still active.
                end
            catch
                % Server gone — close anyway.
            end
            fig = obj.ParentFigure;
            closeTimer = timer('StartDelay', 0.5, ...
                'TimerFcn', @(t,~) Terminal.deferredClose(t, obj, fig));
            start(closeTimer);
        end

        function resp = serverPost(obj, endpoint, data)
            %SERVERPOST Send a POST request to the Go server.
            url = [obj.BaseURL, endpoint];
            resp = webwrite(url, data, obj.WriteOpts);
        end

        function sendToJS(obj, msg)
            %SENDTOJS Send a message to JS by setting HTMLComponent.Data.
            if ~isempty(obj.HTMLComponent) && isvalid(obj.HTMLComponent)
                obj.HTMLComponent.Data = msg;
            end
        end
    end

    methods (Static)
        function install()
            %INSTALL Download the server binary for the current platform.
            arch = computer('arch');
            checksumFile = fullfile(fileparts(mfilename('fullpath')), 'checksums.json');

            if ~isfile(checksumFile)
                error('Terminal:NoChecksums', ...
                    'checksums.json not found at:\n  %s', checksumFile);
            end
            info = jsondecode(fileread(checksumFile));

            if ~isfield(info.binaries, arch)
                error('Terminal:UnsupportedArch', ...
                    'No binary available for architecture "%s".', arch);
            end
            entry = info.binaries.(arch);

            destDir = fullfile(userpath, 'bin');
            if ~isfolder(destDir)
                mkdir(destDir);
            end

            binaryName = Terminal.SERVER_BINARY_NAME;
            if strcmp(arch, 'win64')
                binaryName = [binaryName, '.exe'];
            end
            destPath = fullfile(destDir, binaryName);

            fprintf('Downloading %s for %s ...\n', binaryName, arch);
            websave(destPath, entry.url);

            if ~ispc
                system(sprintf('chmod +x "%s"', destPath));
            end

            if strcmp(entry.sha256, 'placeholder')
                fprintf('  [warning] Checksum verification skipped (placeholder hash).\n');
            else
                Terminal.verifyChecksum(destPath, entry.sha256);
            end

            fprintf('Installed server binary to:\n  %s\n', destPath);
        end

        function update()
            Terminal.install();
        end
    end

    methods (Static, Access = private)
        function htmlDir = extractWebAssets()
            %EXTRACTWEBASSETS Extract web assets from web_assets.mat to a cache dir.
            %   packageToolbox drops .html/.css/.js files, so we bundle them
            %   in a .mat file and extract at runtime.
            cacheDir = fullfile(prefdir, 'matlab-terminal', 'html');
            stampFile = fullfile(prefdir, 'matlab-terminal', '.version');

            % Check if already extracted for this version.
            currentVersion = '0.1.0';
            if isfile(stampFile) && strcmp(strtrim(fileread(stampFile)), currentVersion)
                htmlDir = cacheDir;
                return;
            end

            matFile = fullfile(fileparts(mfilename('fullpath')), 'web_assets.mat');
            if ~isfile(matFile)
                error('Terminal:NoAssets', ...
                    'web_assets.mat not found at:\n  %s\nRe-install the toolbox.', matFile);
            end

            cacheRoot = fullfile(prefdir, 'matlab-terminal');
            fprintf('Extracting Terminal assets to:\n  %s\n', cacheRoot);

            S = load(matFile, 'assets');
            fields = fieldnames(S.assets);
            for i = 1:numel(fields)
                entry = S.assets.(fields{i});
                dst = fullfile(prefdir, 'matlab-terminal', entry.path);
                dstDir = fileparts(dst);
                if ~isfolder(dstDir)
                    mkdir(dstDir);
                end
                fid = fopen(dst, 'w');
                fwrite(fid, entry.data);
                fclose(fid);
                % Make binaries executable.
                if isfield(entry, 'executable') && entry.executable && ~ispc
                    system(sprintf('chmod +x "%s"', dst));
                end
            end

            % Write version stamp.
            fid = fopen(stampFile, 'w');
            fprintf(fid, '%s', currentVersion);
            fclose(fid);

            htmlDir = cacheDir;
        end

        function deferredClose(tmr, obj, fig)
            stop(tmr);
            delete(tmr);
            delete(obj);
            if ~isempty(fig) && isvalid(fig)
                close(fig);
            end
        end

        function binaryPath = findBinary()
            binaryName = Terminal.SERVER_BINARY_NAME;
            if ispc
                binaryName = [binaryName, '.exe'];
            end

            % Check dist/<arch>/ directory (development builds).
            arch = computer('arch');
            candidate = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'dist', arch, binaryName);
            if isfile(candidate)
                binaryPath = candidate;
                return;
            end

            % Check extracted cache (from web_assets.mat).
            candidate = fullfile(prefdir, 'matlab-terminal', 'bin', arch, binaryName);
            if isfile(candidate)
                binaryPath = candidate;
                return;
            end

            % Check userpath/bin (installed via Terminal.install).
            candidate = fullfile(userpath, 'bin', binaryName);
            if isfile(candidate)
                binaryPath = candidate;
                return;
            end

            if ispc
                [st, result] = system(sprintf('where "%s" 2>nul', binaryName));
            else
                [st, result] = system(sprintf('which "%s" 2>/dev/null', binaryName));
            end
            if st == 0
                binaryPath = strtrim(result);
                lines = splitlines(binaryPath);
                binaryPath = lines{1};
                return;
            end

            binaryPath = '';
        end

        function themeConfig = buildThemeConfig()
            fontFamily = 'Consolas, ''DejaVu Sans Mono'', ''Liberation Mono'', monospace';

            try
                s = settings;
                fontSize = s.matlab.fonts.codefont.Size.ActiveValue;
            catch
                fontSize = 14;
            end

            try
                s = settings;
                isDark = s.matlab.editor.colortheme.ActiveValue ~= "light";
            catch
                isDark = false;
            end

            if isDark
                themeConfig = struct( ...
                    'isDark', true, ...
                    'fontFamily', fontFamily, ...
                    'fontSize', fontSize, ...
                    'background',  '#1e1e1e', ...
                    'foreground',  '#d4d4d4', ...
                    'cursor',      '#aeafad', ...
                    'selectionBackground', '#264f78');
            else
                themeConfig = struct( ...
                    'isDark', false, ...
                    'fontFamily', fontFamily, ...
                    'fontSize', fontSize, ...
                    'background',  '#ffffff', ...
                    'foreground',  '#333333', ...
                    'cursor',      '#333333', ...
                    'selectionBackground', '#add6ff');
            end
        end

        function verifyChecksum(filePath, expectedHash)
            if ispc
                [~, result] = system(sprintf('certutil -hashfile "%s" SHA256', filePath));
                lines = splitlines(strtrim(result));
                if numel(lines) >= 2
                    actualHash = strtrim(lines{2});
                else
                    warning('Terminal:ChecksumFailed', 'Could not compute checksum.');
                    return;
                end
            elseif ismac
                [~, result] = system(sprintf('shasum -a 256 "%s"', filePath));
                parts = strsplit(strtrim(result));
                actualHash = parts{1};
            else
                [~, result] = system(sprintf('sha256sum "%s"', filePath));
                parts = strsplit(strtrim(result));
                actualHash = parts{1};
            end

            if ~strcmpi(actualHash, expectedHash)
                warning('Terminal:ChecksumMismatch', ...
                    'Checksum mismatch!\n  Expected: %s\n  Actual:   %s', ...
                    expectedHash, actualHash);
            else
                fprintf('  Checksum verified.\n');
            end
        end
    end
end
