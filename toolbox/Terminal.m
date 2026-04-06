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
    %     Shell       - Shell program to run. Can be a name on PATH or an
    %                   absolute path. Default: system shell ($SHELL on
    %                   Unix, %COMSPEC% on Windows).
    %
    %                   Common values by platform:
    %                     Linux/macOS: "bash", "zsh", "sh", "fish",
    %                                  "/bin/bash", "/usr/bin/zsh"
    %                     Windows:     "cmd.exe", "powershell.exe", "pwsh.exe",
    %                                  "wsl.exe"
    %
    %   Static methods:
    %     Terminal.install()  — download the server binary for this platform
    %     Terminal.update()   — re-download the server binary
    %
    %   Examples:
    %     t = Terminal();
    %     t = Terminal(Name="Git", WindowStyle="normal");
    %     t = Terminal(Shell="zsh");
    %     t = Terminal(Shell="powershell.exe");
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
        OutQueue cell = {}  % queued messages from JS to send to server (legacy only)
        UseEvents logical = false  % true if R2023a+ event API is available
        ThemeConfig        % cached theme config for re-init on HTML reload
    end

    properties (SetAccess = private)
        Shell string        % shell program for new sessions (empty = server default)
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
                options.Shell (1,1) string = ""
            end

            obj.Shell = options.Shell;

            % --- Validate shell if specified, resolve default if not ---
            if obj.Shell ~= ""
                Terminal.validateShell(obj.Shell);
            else
                obj.Shell = Terminal.defaultShell();
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
            readyFile = [tempname, '.txt'];
            args = sprintf('--token "%s" --env "MATLAB_PID=%s" --env "MATLAB_ROOT=%s" --ready-file "%s"', ...
                obj.AuthToken, matlabPid, matlabRoot, readyFile);

            logFile = [tempname, '.log'];
            if ispc
                % Windows: use a temp batch file to run in background.
                batFile = [tempname, '.bat'];
                fid = fopen(batFile, 'w');
                fprintf(fid, '@"%s" %s > "%s" 2>&1\n', obj.ServerBinary, args, logFile);
                fclose(fid);
                system(sprintf('start "" /b cmd /c call "%s"', batFile));
            else
                system(sprintf('"%s" %s > "%s" 2>&1 &', obj.ServerBinary, args, logFile));
            end

            % Wait for the server to write PID and PORT to the ready file.
            % The server writes and closes this file immediately, so there
            % is no file locking conflict on Windows.
            serverPid = [];
            port = [];
            maxWait = 5;
            elapsed = 0;
            while elapsed < maxWait
                pause(0.2);
                elapsed = elapsed + 0.2;
                if isfile(readyFile)
                    raw = fileread(readyFile);
                    pidTok = regexp(raw, 'PID:(\d+)', 'tokens', 'once');
                    portTok = regexp(raw, 'PORT:(\d+)', 'tokens', 'once');
                    if ~isempty(pidTok)
                        serverPid = str2double(pidTok{1});
                    end
                    if ~isempty(portTok)
                        port = str2double(portTok{1});
                        break;
                    end
                end
            end

            % Clean up temp files.
            if isfile(readyFile), delete(readyFile); end
            if ispc && exist('batFile', 'var') && isfile(batFile)
                delete(batFile);
            end

            if isempty(port)
                if ~isempty(serverPid)
                    Terminal.killProcess(serverPid);
                end
                % Read server log for diagnostics.
                serverLog = '';
                if isfile(logFile)
                    try
                        serverLog = fileread(logFile);
                    catch
                    end
                    delete(logFile);
                end
                if serverLog ~= ""
                    error('Terminal:NoPort', ...
                        'Server did not report a port within %d seconds.\nServer output:\n%s', ...
                        maxWait, serverLog);
                else
                    error('Terminal:NoPort', ...
                        'Server did not report a port within %d seconds.', maxWait);
                end
            end
            % Clean up log file on success (server keeps running).
            % Keep it around — it's useful for debugging if something
            % goes wrong later. It will be cleaned up by the OS.

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
                Terminal.killProcess(obj.ServerProcess.pid);
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

            obj.ThemeConfig = themeConfig;
            obj.UseEvents = ~isMATLABReleaseOlderThan('R2023a');

            if obj.UseEvents
                % R2023a+: event-based API — no data loss, no buffering needed.
                obj.HTMLComponent.HTMLEventReceivedFcn = @(~, event) obj.onHTMLEvent(event);
                sendEventToHTMLSource(obj.HTMLComponent, 'init', themeConfig);
            else
                % Legacy: Data channel (last-write-wins).
                obj.HTMLComponent.DataChangedFcn = @(src, ~) obj.onJSMessage(src);
                obj.HTMLComponent.Data = struct('type', 'init', 'theme', themeConfig);
            end

            % Start polling for server output.
            obj.PollTimer = timer( ...
                'ExecutionMode', 'fixedSpacing', ...
                'Period', obj.POLL_INTERVAL, ...
                'TimerFcn', @(~,~) obj.pollOutput(), ...
                'ErrorFcn', @(~,~) []);
            start(obj.PollTimer);
        end

        function onHTMLEvent(obj, event)
            %ONHTMLEVENT Handle events from JS via the R2023a+ event API.
            %   Still queued for the poll timer to avoid concurrent webwrite
            %   calls, but no JS-side data loss since events don't overwrite.
            msg = event.HTMLEventData;
            msg.type = event.HTMLEventName;
            obj.OutQueue{end+1} = msg;
        end

        function onJSMessage(obj, src)
            %ONJSMESSAGE Handle messages from JS via the legacy Data channel.
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
                if ~isempty(obj.OutQueue)
                    if obj.UseEvents
                        % R2023a+: drain all — event API doesn't overwrite.
                        queue = obj.OutQueue;
                        obj.OutQueue = {};
                        for i = 1:numel(queue)
                            obj.processJSMessage(queue{i});
                        end
                    else
                        % Legacy: one at a time, then return so JS can
                        % read the response before Data is overwritten.
                        msg = obj.OutQueue{1};
                        obj.OutQueue(1) = [];
                        obj.processJSMessage(msg);
                        return;
                    end
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
                case 'ready'
                    % HTML page (re)loaded — re-send init so JS can start.
                    % Send directly (not via sendToJS) to match the format
                    % that deferredInit uses for the init event.
                    if obj.UseEvents
                        sendEventToHTMLSource(obj.HTMLComponent, 'init', obj.ThemeConfig);
                    else
                        obj.HTMLComponent.Data = struct('type', 'init', 'theme', obj.ThemeConfig);
                    end
                case 'create'
                    createReq = struct('cols', 80, 'rows', 24, 'shell', obj.Shell);
                    resp = obj.serverPost('/api/create', createReq);
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
            %SENDTOJS Send a message to JS.
            if isempty(obj.HTMLComponent) || ~isvalid(obj.HTMLComponent)
                return;
            end
            if obj.UseEvents
                sendEventToHTMLSource(obj.HTMLComponent, msg.type, msg);
            else
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
            cacheRoot = fullfile(prefdir, 'matlab-terminal');
            cacheDir = fullfile(cacheRoot, 'html');
            stampFile = fullfile(cacheRoot, '.extracted');

            matFile = fullfile(fileparts(mfilename('fullpath')), 'web_assets.mat');
            if ~isfile(matFile)
                % Running from source — no .mat file needed.
                htmlDir = cacheDir;
                return;
            end

            % Re-extract if the .mat file is newer than our stamp,
            % meaning a new toolbox version was installed.
            matInfo = dir(matFile);
            needsExtract = true;
            if isfile(stampFile)
                stampInfo = dir(stampFile);
                needsExtract = matInfo.datenum > stampInfo.datenum;
            end

            if ~needsExtract
                htmlDir = cacheDir;
                return;
            end

            % Wipe old cache entirely before extracting.
            if isfolder(cacheRoot)
                fprintf('Clearing old Terminal cache at:\n  %s\n', cacheRoot);
                rmdir(cacheRoot, 's');
            end

            fprintf('Extracting Terminal assets to:\n  %s\n', cacheRoot);

            S = load(matFile, 'assets');
            fields = fieldnames(S.assets);
            for i = 1:numel(fields)
                entry = S.assets.(fields{i});
                dst = fullfile(cacheRoot, entry.path);
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

            % Touch stamp file so we know this extraction is current.
            fid = fopen(stampFile, 'w');
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

            isDark = false;
            try
                % Check default figure background luminance (no side effects).
                c = get(groot, 'defaultFigureColor');
                luminance = 0.2126*c(1) + 0.7152*c(2) + 0.0722*c(3);
                isDark = luminance < 0.5;
            catch
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

        function shell = defaultShell()
            %DEFAULTSHELL Return the system default shell (mirrors server logic).
            if ispc
                shell = string(getenv('COMSPEC'));
                if shell == ""
                    shell = "cmd.exe";
                end
            else
                shell = string(getenv('SHELL'));
                if shell == ""
                    shell = "/bin/sh";
                end
            end
        end

        function validateShell(shell)
            %VALIDATESHELL Error if the given shell is not found on the system.
            if isfile(shell)
                return;  % Absolute path exists.
            end
            % Check if it's on PATH.
            if ispc
                [st, ~] = system(sprintf('where "%s" >nul 2>&1', shell));
            else
                [st, ~] = system(sprintf('which "%s" >/dev/null 2>&1', shell));
            end
            if st ~= 0
                if ispc
                    common = 'cmd.exe, powershell.exe, pwsh.exe, wsl.exe';
                else
                    common = 'bash, zsh, sh, fish';
                end
                error('Terminal:ShellNotFound', ...
                    'Shell "%s" not found.\nCommon shells for this platform: %s', ...
                    shell, common);
            end
        end

        function killProcess(pid)
            %KILLPROCESS Terminate a process by PID (cross-platform).
            if ispc
                system(sprintf('taskkill /PID %d /F >nul 2>&1', pid));
            else
                system(sprintf('kill %d 2>/dev/null', pid));
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
