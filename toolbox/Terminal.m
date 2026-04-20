% Copyright 2026 The MathWorks, Inc.

classdef Terminal < handle
    %TERMINAL Embeds a system terminal inside a MATLAB figure using uihtml.
    %
    %   t = Terminal()                    — docked terminal with default name
    %   t = Terminal(Name="Build")        — docked terminal with custom name
    %   t = Terminal(WindowStyle="normal") — undocked terminal in its own window
    %   t = Terminal(MCP=true)            — share MATLAB session for AI agents
    %   t = Terminal(parent)              — terminal inside an existing figure/panel
    %   delete(t)                         — closes the terminal and kills the server
    %
    %   Name-Value Arguments:
    %     Name        - Title of the terminal window (default: "Terminal")
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
    %     Theme       - Color theme. Default: "auto" (follows MATLAB light/dark).
    %                   Built-in: "light", "dark"
    %                   Presets:  "dracula", "monokai", "solarized-dark",
    %                             "solarized-light", "nord", "gruvbox-dark",
    %                             "one-dark", "tokyo-night", "catppuccin-mocha"
    %                   Custom:   struct with fields: background, foreground,
    %                             cursor, selectionBackground, and ANSI colors
    %                             (black, red, green, ..., brightWhite)
    %     MCP         - Share the running MATLAB session so AI agents can
    %                   connect to it via the MATLAB MCP Core Server with
    %                   --matlab-session-mode=existing. Requires the MATLAB
    %                   MCP Core Server Toolkit. Default: false.
    %
    %   Static methods:
    %     Terminal.version()  — return the installed toolbox version string
    %     Terminal.list()     — return handles to all running terminals
    %     Terminal.closeAll() — close all running terminals
    %     Terminal.update()          — update to the latest stable release from GitHub
    %     Terminal.update("1.2.0")  — install a specific version (release candidates too)
    %     Terminal.versions()       — list available releases on GitHub
    %     Terminal.themes()   — list available theme names
    %     Terminal.setDefaultTheme("dracula") — set default for new terminals
    %     Terminal.getDefaultTheme()          — get current default theme
    %     Terminal.verify()         — verify binary integrity against GitHub release
    %     Terminal.test()          — run the built-in test suite with report
    %
    %   Examples:
    %     t = Terminal();
    %     t = Terminal(Name="Git", WindowStyle="normal");
    %     t = Terminal(Shell="zsh");
    %     t = Terminal(Shell="powershell.exe");
    %     t = Terminal(Theme="dracula");
    %     t = Terminal(Theme="solarized-light");
    %     t.Theme = "monokai";    % change theme after creation
    %     Terminal.setDefaultTheme("dracula");  % persist across sessions
    %     Terminal.getDefaultTheme();
    %     t = Terminal(MCP=true);
    %     delete(t);
    %     Terminal.update();
    %     Terminal.update("0.8.0-rc1");
    %     Terminal.versions();
    %     Terminal.verify();

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
        MCPCommand         % command to pre-populate in the first terminal session
        InitTimer          % one-shot timer for deferred post-constructor init
        MCPTimer           % one-shot timer for delayed MCP hint
        ThemePollCount double = 0  % tick counter for periodic theme check
        LastFigureColor    % cached groot DefaultFigureColor for change detection
        ConsecutivePollFailures double = 0  % poll failure counter for server death detection
        IsRestarting logical = false  % true while server restart is in progress
    end

    properties (SetAccess = private)
        Shell string        % shell program for new sessions (empty = server default)
    end

    properties
        Theme = "auto"      % "auto" | "light" | "dark" | preset name | struct
    end

    properties (Constant, Access = private)
        DEFAULT_IDLE_TIMEOUT = 30   % seconds
        SERVER_BINARY_NAME = 'matlab-terminal-server'
        POLL_INTERVAL = 0.1         % 100ms polling interval
        THEME_CHECK_TICKS = 50     % check theme every 50 ticks (5 seconds)
        TOOLBOX_ID = '9e8f4a2b-3c1d-4e5f-a6b7-8c9d0e1f2a3b'
        GITHUB_REPO = 'prabhakk-mw/matlab-terminal'
        MCP_TOOLKIT_NAME = 'MATLAB MCP Core Server Toolkit'
        MCP_TOOLKIT_URL = 'https://github.com/matlab/matlab-mcp-core-server/releases/latest'
        MCP_GITHUB_API = 'https://api.github.com/repos/matlab/matlab-mcp-core-server/releases/latest'
        MCP_SERVER_BINARY = 'matlab-mcp-core-server'
        % Minimum server version required for --matlab-session-mode=existing.
        % This is a fragile floor check — it guards against stale binaries
        % but cannot guarantee compatibility with future server versions.
        MCP_MIN_SERVER_VERSION = '0.8.0'
    end

    methods
        function obj = Terminal(parent, options)
            %TERMINAL Construct a terminal instance.
            arguments
                parent = []
                options.Name (1,1) string = "Terminal"
                options.WindowStyle (1,1) string {mustBeMember(options.WindowStyle, ["docked", "normal"])} = "docked"
                options.Shell (1,1) string = ""
                options.Theme = missing
                options.MCP (1,1) logical = false
            end

            obj.Shell = options.Shell;

            % Use saved default theme if not explicitly provided.
            if ismissing(options.Theme)
                options.Theme = Terminal.getDefaultTheme();
            end
            internal.Themes.validate(options.Theme);
            obj.Theme = options.Theme;

            % --- Validate shell if specified, resolve default if not ---
            if obj.Shell ~= ""
                Terminal.validateShell(obj.Shell);
            else
                obj.Shell = Terminal.defaultShell();
            end

            % --- MCP: share MATLAB session for AI agents ---
            if options.MCP
                serverBin = Terminal.setupMCP();
                extensionFile = fullfile( ...
                    fileparts(which('TerminalMCPTools.matlab_editor_list')), ...
                    'matlab-editor-tools.json');
                obj.MCPCommand = sprintf( ...
                    'claude mcp add --transport stdio matlab -- "%s" --matlab-session-mode=existing --extension-file="%s"', ...
                    serverBin, extensionFile);
            end

            % --- Parent container ---
            if isempty(parent)
                parent = uifigure('Name', options.Name, ...
                    'Position', [100 100 800 500]);
                try
                    parent.WindowStyle = options.WindowStyle;
                catch
                    if options.WindowStyle == "docked"
                        warning('Terminal:DockNotSupported', ...
                            'Docked window style is not supported in this MATLAB release. Using normal window.');
                    end
                end
            end
            obj.ParentFigure = parent;

            % --- Auth token (32-char hex, cryptographically random) ---
            obj.AuthToken = Terminal.generateToken();

            % --- Extract bundled assets if needed ---
            Terminal.extractWebAssets();

            % --- Locate the server binary ---
            obj.ServerBinary = Terminal.findBinary();
            if isempty(obj.ServerBinary)
                error('Terminal:BinaryNotFound', ...
                    ['Server binary "%s" not found.\n' ...
                     'The toolbox installation may be corrupted.\n' ...
                     'Run  Terminal.update()  to reinstall.'], ...
                    Terminal.SERVER_BINARY_NAME);
            end

            % --- Build environment info ---
            matlabPid = num2str(feature('getpid'));
            matlabRoot = matlabroot;

            % --- Start the server process ---
            readyFile = [tempname, '.txt'];
            args = sprintf('--env "MATLAB_PID=%s" --env "MATLAB_ROOT=%s" --ready-file "%s"', ...
                matlabPid, matlabRoot, readyFile);

            % Pass the token via environment variable so it is not visible
            % in the process list (ps, tasklist, /proc/*/cmdline).
            setenv('MATLAB_TERMINAL_TOKEN', obj.AuthToken);

            logFile = [tempname, '.log'];
            if ispc
                % Windows: use a temp batch file to run in background.
                batFile = [tempname, '.bat'];
                fid = fopen(batFile, 'w');
                fprintf(fid, '@"%s" %s > "%s" 2>&1\n', obj.ServerBinary, args, logFile);
                fclose(fid);
                system(sprintf('start "" /b cmd /c call "%s"', batFile));
            else
                % Use /bin/sh explicitly — MATLAB's system() inherits
                % the user's login shell, and tcsh/csh don't support
                % the 2>&1 redirection syntax.
                cmd = sprintf('"%s" %s > "%s" 2>&1 &', obj.ServerBinary, args, logFile);
                system(sprintf('/bin/sh -c ''%s''', cmd));
            end

            % Clear the env var so it's not inherited by other processes.
            setenv('MATLAB_TERMINAL_TOKEN', '');

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
            themeConfig = internal.Themes.resolve(obj.Theme);

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
            if isprop(obj.ParentFigure, 'CloseRequestFcn')
                obj.ParentFigure.CloseRequestFcn = @(~,~) delete(obj);
            end

            % Register this instance.
            Terminal.registry('add', obj);

            % Use a one-shot timer to initialize AFTER the constructor returns.
            % This prevents DataChangedFcn from firing during construction.
            obj.InitTimer = timer('StartDelay', 1.5, ...
                'TimerFcn', @(t,~) obj.deferredInit(t, themeConfig));
            start(obj.InitTimer);
        end

        function set.Theme(obj, value)
            internal.Themes.validate(value);
            obj.Theme = value; %#ok<MCSUP>
            % Push live update if already initialized.
            if ~isempty(obj.ThemeConfig) %#ok<MCSUP>
                newConfig = internal.Themes.resolve(value);
                obj.ThemeConfig = newConfig; %#ok<MCSUP>
                obj.sendToJS(struct('type', 'theme', 'theme', newConfig)); %#ok<MCSUP>
            end
        end

        function delete(obj)
            %DELETE Clean up: stop timer, kill server, close figure.
            Terminal.registry('remove', obj);
            if ~isempty(obj.InitTimer) && isvalid(obj.InitTimer)
                stop(obj.InitTimer);
                delete(obj.InitTimer);
            end
            if ~isempty(obj.PollTimer) && isvalid(obj.PollTimer)
                stop(obj.PollTimer);
                delete(obj.PollTimer);
            end
            if ~isempty(obj.MCPTimer) && isvalid(obj.MCPTimer)
                stop(obj.MCPTimer);
                delete(obj.MCPTimer);
            end
            if ~isempty(obj.ServerProcess) && isstruct(obj.ServerProcess) ...
                    && isfield(obj.ServerProcess, 'pid') && ~isnan(obj.ServerProcess.pid)
                Terminal.killProcess(obj.ServerProcess.pid);
            end
            if ~isempty(obj.ParentFigure) && isvalid(obj.ParentFigure)
                if isprop(obj.ParentFigure, 'CloseRequestFcn')
                    obj.ParentFigure.CloseRequestFcn = '';
                end
                delete(obj.ParentFigure);
            end
        end
    end

    methods (Access = private)
        function deferredInit(obj, initTimer, themeConfig)
            %DEFERREDINIT Called after constructor returns to avoid reentrant callbacks.
            stop(initTimer);
            delete(initTimer);
            obj.InitTimer = [];

            if ~isvalid(obj)
                return;
            end

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

            % Snapshot the current figure color for theme change detection.
            try
                obj.LastFigureColor = get(groot, 'defaultFigureColor');
            catch
                obj.LastFigureColor = [];
            end

            % Start polling for server output.
            obj.PollTimer = timer( ...
                'ExecutionMode', 'fixedSpacing', ...
                'Period', obj.POLL_INTERVAL, ...
                'TimerFcn', @(~,~) obj.pollOutput(), ...
                'ErrorFcn', @(~,~) []);
            start(obj.PollTimer);
        end

        function checkThemeChanged(obj)
            %CHECKTHEMECHANGED Compare current figure color to cached value.
            try
                c = get(groot, 'defaultFigureColor');
            catch
                return;
            end
            if isequal(c, obj.LastFigureColor)
                return;
            end
            obj.LastFigureColor = c;
            newConfig = internal.Themes.resolve(obj.Theme);
            obj.ThemeConfig = newConfig;
            obj.sendToJS(struct('type', 'theme', ...
                'theme', newConfig));
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
                % Skip normal polling while a restart is in progress.
                if obj.IsRestarting
                    return;
                end

                % --- Periodic theme change detection (only in auto mode) ---
                if obj.Theme == "auto"
                    obj.ThemePollCount = obj.ThemePollCount + 1;
                    if obj.ThemePollCount >= obj.THEME_CHECK_TICKS
                        obj.ThemePollCount = 0;
                        obj.checkThemeChanged();
                    end
                end

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
                obj.ConsecutivePollFailures = 0;
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
                obj.ConsecutivePollFailures = obj.ConsecutivePollFailures + 1;
                if obj.ConsecutivePollFailures >= 50
                    obj.tryRestartServer();
                end
            end
        end

        function tryRestartServer(obj)
            %TRYRESTARTSERVER Detect dead server and relaunch it.
            %   Called after 5 consecutive poll failures. Checks if the
            %   server PID is still alive; if not, relaunches the binary
            %   and lets the existing ready/init flow create fresh sessions.
            obj.IsRestarting = true;
            obj.ConsecutivePollFailures = 0;

            % Check if server process is still alive.
            if ~isempty(obj.ServerProcess) && isstruct(obj.ServerProcess) ...
                    && isfield(obj.ServerProcess, 'pid') && ~isnan(obj.ServerProcess.pid)
                if Terminal.isProcessAlive(obj.ServerProcess.pid)
                    % Server is alive but unresponsive — don't restart.
                    obj.IsRestarting = false;
                    return;
                end
            end

            % Show restarting overlay in JS.
            obj.sendToJS(struct('type', 'restarting'));

            % Relaunch the server binary.
            try
                matlabPid = num2str(feature('getpid'));
                matlabRoot = matlabroot;
                readyFile = [tempname, '.txt'];
                args = sprintf('--env "MATLAB_PID=%s" --env "MATLAB_ROOT=%s" --ready-file "%s"', ...
                    matlabPid, matlabRoot, readyFile);

                setenv('MATLAB_TERMINAL_TOKEN', obj.AuthToken);

                logFile = [tempname, '.log'];
                if ispc
                    batFile = [tempname, '.bat'];
                    fid = fopen(batFile, 'w');
                    fprintf(fid, '@"%s" %s > "%s" 2>&1\n', obj.ServerBinary, args, logFile);
                    fclose(fid);
                    system(sprintf('start "" /b cmd /c call "%s"', batFile));
                else
                    cmd = sprintf('"%s" %s > "%s" 2>&1 &', obj.ServerBinary, args, logFile);
                    system(sprintf('/bin/sh -c ''%s''', cmd));
                end

                setenv('MATLAB_TERMINAL_TOKEN', '');

                % Wait for the server to write PID and PORT.
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

                if isfile(readyFile), delete(readyFile); end
                if ispc && exist('batFile', 'var') && isfile(batFile)
                    delete(batFile);
                end

                if isempty(port)
                    if ~isempty(serverPid)
                        Terminal.killProcess(serverPid);
                    end
                    obj.IsRestarting = false;
                    return;
                end

                obj.ServerProcess = struct('pid', serverPid, 'port', port);
                obj.BaseURL = sprintf('http://127.0.0.1:%d', port);
                obj.PollSeq = 0;

                % Update weboptions with same auth token.
                obj.ReadOpts = weboptions('HeaderFields', {'Authorization', obj.AuthToken}, ...
                    'Timeout', 2, 'ContentType', 'json');
                obj.WriteOpts = weboptions('HeaderFields', {'Authorization', obj.AuthToken}, ...
                    'MediaType', 'application/json', 'Timeout', 2);
            catch
                obj.IsRestarting = false;
                return;
            end

            obj.IsRestarting = false;

            % Send init directly — the page didn't reload so setup()
            % won't fire. The 'restarting' handler already reset
            % initialized=false and disposed old tabs.
            initData = obj.ThemeConfig;
            if obj.UseEvents
                sendEventToHTMLSource(obj.HTMLComponent, 'init', initData);
            else
                obj.HTMLComponent.Data = struct('type', 'init', 'theme', initData);
            end
        end

        function processJSMessage(obj, msg)
            %PROCESSJSMESSAGE Execute a single queued JS message.
            switch msg.type
                case 'ready'
                    % HTML page (re)loaded — re-send init so JS can start.
                    % Query the server for existing sessions so JS can
                    % reconnect instead of creating new tabs.
                    initData = obj.ThemeConfig;
                    try
                        url = [obj.BaseURL, '/api/sessions'];
                        resp = webread(url, obj.ReadOpts);
                        if isfield(resp, 'ids') && ~isempty(resp.ids)
                            if ischar(resp.ids) || isstring(resp.ids)
                                ids = {char(resp.ids)};
                            else
                                ids = resp.ids;
                            end
                            initData.existingSessionIds = ids;
                            % Fetch scrollback for each session.
                            scrollbacks = struct();
                            for k = 1:numel(ids)
                                sid = ids{k};
                                try
                                    sbUrl = sprintf('%s/api/scrollback?id=%s', obj.BaseURL, sid);
                                    sbResp = webread(sbUrl, obj.ReadOpts);
                                    if isfield(sbResp, 'data')
                                        scrollbacks.(sid) = sbResp.data;
                                    end
                                catch
                                end
                            end
                            initData.scrollbacks = scrollbacks;
                        end
                    catch
                        % Server may not be ready yet — JS will create a
                        % new tab as usual.
                    end
                    if obj.UseEvents
                        sendEventToHTMLSource(obj.HTMLComponent, 'init', initData);
                    else
                        obj.HTMLComponent.Data = struct('type', 'init', 'theme', initData);
                    end
                case 'create'
                    createReq = struct('cols', 80, 'rows', 24, 'shell', obj.Shell);
                    resp = obj.serverPost('/api/create', createReq);
                    if ~isempty(resp) && isfield(resp, 'id')
                        obj.sendToJS(struct('type', 'created', 'id', resp.id));
                        % Pre-populate MCP registration command in the
                        % first session. Delayed so the shell prompt is
                        % ready. Sent without a newline — user hits Enter.
                        if ~isempty(obj.MCPCommand)
                            sid = resp.id;
                            cmd = obj.MCPCommand;
                            obj.MCPCommand = [];  % only for the first session
                            obj.MCPTimer = timer('StartDelay', 1.0, ...
                                'TimerFcn', @(t,~) obj.sendMCPHint(t, sid, cmd));
                            start(obj.MCPTimer);
                        end
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

        function sendMCPHint(obj, tmr, sessionId, cmd)
            %SENDMCPHINT Pre-populate MCP registration command in a session.
            stop(tmr);
            delete(tmr);
            obj.MCPTimer = [];
            if ~isvalid(obj)
                return;
            end
            try
                obj.serverPost('/api/input', struct('id', sessionId, 'data', cmd));
            catch
            end
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
        function v = version()
            %VERSION Return the installed toolbox version string.
            %
            %   v = Terminal.version()
            v = TerminalVersion();
        end

        function terminals = list()
            %LIST Return handles to all running Terminal instances.
            %
            %   terminals = Terminal.list()
            %
            %   Returns a (possibly empty) array of Terminal handles.
            terminals = Terminal.registry('get');
        end

        function closeAll()
            %CLOSEALL Close all running Terminal instances.
            %
            %   Terminal.closeAll()
            terminals = Terminal.list();
            for i = 1:numel(terminals)
                delete(terminals(i));
            end
        end

        function names = themes()
            %THEMES List available built-in theme names.
            %
            %   Terminal.themes()
            names = internal.Themes.list();
        end

        function setDefaultTheme(theme)
            %SETDEFAULTTHEME Set the default theme for new Terminal instances.
            %
            %   Terminal.setDefaultTheme("dracula")
            %   Terminal.setDefaultTheme("auto")      — reset to default
            %
            %   The default theme persists across MATLAB sessions. New
            %   terminals use this theme unless overridden with Theme=.
            internal.Themes.validate(theme);
            if isstruct(theme)
                setpref('Terminal', 'Theme', theme);
            else
                setpref('Terminal', 'Theme', string(theme));
            end
        end

        function theme = getDefaultTheme()
            %GETDEFAULTTHEME Return the current default theme.
            %
            %   Terminal.getDefaultTheme()
            if ispref('Terminal', 'Theme')
                theme = getpref('Terminal', 'Theme');
            else
                theme = "auto";
            end
        end

        function update(version)
            %UPDATE Check for and install a toolbox version from GitHub.
            %
            %   Terminal.update()          — update to the latest stable release
            %   Terminal.update("1.2.0")   — install a specific version
            %   Terminal.update("v1.2.0")  — "v" prefix is accepted
            %   Terminal.update("1.2.0-rc1") — release candidates work too
            %
            %   When called without arguments, only releases marked as
            %   "Latest" on GitHub are considered (pre-releases and drafts
            %   are skipped). To install a pre-release, specify its version
            %   explicitly.
            arguments
                version (1,1) string = ""
            end

            disp('Checking for updates...');

            if version == ""
                release = Terminal.fetchLatestRelease();
            else
                release = Terminal.fetchRelease(version);
            end

            targetVersion = Terminal.tagToVersion(release.tag_name);
            installedVersion = string(Terminal.version());

            fprintf('  Installed version: %s\n', installedVersion);
            fprintf('  Target version:    %s\n', targetVersion);

            % Find the .mltbx asset in the release.
            mltbxURL = Terminal.findMltbxAsset(release);

            % Ask for confirmation.
            if targetVersion == installedVersion
                disp('Already up to date.');
                reply = input('Reinstall current version? (y/n): ', 's');
            else
                reply = input(sprintf('Update from %s to %s? (y/n): ', ...
                    installedVersion, targetVersion), 's');
            end
            if ~strcmpi(reply, 'y')
                disp('Update cancelled.');
                return;
            end

            % Step 1: Download BEFORE uninstalling (safe ordering).
            disp('Step 1/5: Downloading release...');
            tmpFile = fullfile(tempdir, 'Terminal.mltbx');
            try
                websave(tmpFile, mltbxURL);
            catch me
                error('Terminal:UpdateFailed', ...
                    'Download failed (installed version unchanged):\n  %s', me.message);
            end

            % Step 2: Close all open terminals.
            disp('Step 2/5: Closing all open terminals...');
            Terminal.closeAll();

            % Step 3: Uninstall current toolbox.
            disp('Step 3/5: Uninstalling current version...');
            try
                matlab.addons.uninstall(Terminal.TOOLBOX_ID);
            catch
                % May fail if running from source or not installed as toolbox.
            end

            % Step 4: Clear cached assets.
            cacheRoot = fullfile(prefdir, 'matlab-terminal');
            if isfolder(cacheRoot)
                disp('Step 4/5: Clearing cached assets...');
                rmdir(cacheRoot, 's');
            else
                disp('Step 4/5: No cached assets to clear.');
            end

            % Step 5: Install the new version.
            disp('Step 5/5: Installing new version...');
            try
                matlab.addons.install(tmpFile);
            catch me
                fprintf(2, 'Installation failed. The .mltbx is saved at:\n  %s\n', tmpFile);
                fprintf(2, 'You can install it manually: matlab.addons.install("%s")\n', tmpFile);
                error('Terminal:UpdateFailed', ...
                    'Installation failed:\n  %s', me.message);
            end
            delete(tmpFile);
            rehash toolboxcache;

            fprintf('Successfully updated Terminal to version %s.\n', targetVersion);
        end

        function versions()
            %VERSIONS List available Terminal releases on GitHub.
            %
            %   Terminal.versions()
            %
            %   Displays a table of available releases with version,
            %   date, and whether each is a pre-release or the latest.

            url = sprintf('https://api.github.com/repos/%s/releases', ...
                Terminal.GITHUB_REPO);
            try
                opts = weboptions('ContentType', 'json', 'Timeout', 10);
                releases = webread(url, opts);
            catch me
                error('Terminal:VersionsFailed', ...
                    'Could not reach GitHub:\n  %s', me.message);
            end

            if isempty(releases)
                disp('No releases found.');
                return;
            end

            installedVersion = string(Terminal.version());
            fprintf('  Installed: %s\n\n', installedVersion);
            fprintf('  %-14s %-12s %s\n', 'VERSION', 'DATE', 'LABEL');
            fprintf('  %-14s %-12s %s\n', '-------', '----', '-----');

            for i = 1:numel(releases)
                if iscell(releases)
                    r = releases{i};
                else
                    r = releases(i);
                end
                v = Terminal.tagToVersion(r.tag_name);
                % Parse date from ISO 8601 published_at.
                dateStr = extractBefore(string(r.published_at), 'T');

                labels = {};
                if isfield(r, 'prerelease') && r.prerelease
                    labels{end+1} = 'pre-release'; %#ok<AGROW>
                end
                if v == installedVersion
                    labels{end+1} = 'installed'; %#ok<AGROW>
                end
                label = strjoin(labels, ', ');
                fprintf('  %-14s %-12s %s\n', v, dateStr, label);
            end

            % Identify which is the "Latest" release (what update() would pick).
            try
                latestUrl = sprintf('https://api.github.com/repos/%s/releases/latest', ...
                    Terminal.GITHUB_REPO);
                latest = webread(latestUrl, opts);
                latestV = Terminal.tagToVersion(latest.tag_name);
                fprintf('\n  Latest stable release: %s\n', latestV);
            catch
            end
        end

        function verify()
            %VERIFY Verify the installed server binary against the GitHub release.
            %
            %   Terminal.verify()
            %
            %   Checks the SHA-256 hash of the installed server binary against
            %   the checksums published on the matching GitHub release. If
            %   slsa-verifier is available on the system PATH, also performs
            %   full SLSA provenance verification.

            v = Terminal.version();
            if v == "0.0.0-dev"
                fprintf('Skipping verification: running from source (version 0.0.0-dev).\n');
                return;
            end

            % Ensure assets are extracted (needed on fresh install).
            Terminal.extractWebAssets();

            % Locate the installed binary.
            binaryPath = Terminal.findBinary();
            if isempty(binaryPath)
                fprintf(2, 'Server binary not found. Cannot verify.\n');
                return;
            end
            fprintf('Installed version: %s\n', v);
            fprintf('Binary path:       %s\n\n', binaryPath);

            % Compute local SHA-256.
            localHash = Terminal.sha256file(binaryPath);
            fprintf('Local SHA-256:     %s\n', localHash);

            % Determine expected asset name for this platform.
            arch = computer('arch');
            switch arch
                case 'glnxa64', assetName = 'matlab-terminal-server-glnxa64';
                case 'maci64',  assetName = 'matlab-terminal-server-maci64';
                case 'maca64',  assetName = 'matlab-terminal-server-maca64';
                case 'win64',   assetName = 'matlab-terminal-server-win64.exe';
                otherwise
                    fprintf(2, 'Unknown platform: %s\n', arch);
                    return;
            end

            % Fetch checksums.txt from the matching GitHub release.
            tag = "v" + v;
            checksumsURL = sprintf( ...
                'https://github.com/%s/releases/download/%s/checksums.txt', ...
                Terminal.GITHUB_REPO, tag);
            fprintf('Fetching checksums from %s release...\n', tag);
            try
                raw = webread(checksumsURL, weboptions('ContentType', 'text', 'Timeout', 10));
            catch me
                fprintf(2, 'Could not fetch checksums.txt from release %s:\n  %s\n', tag, me.message);
                fprintf(2, 'The release may not include checksums (added in v0.11.0).\n');
                return;
            end

            % Parse checksums.txt (format: "<hash>  <filename>" per line).
            lines = splitlines(string(raw));
            expectedHash = '';
            for i = 1:numel(lines)
                line = strtrim(lines(i));
                if line == ""
                    continue;
                end
                parts = split(line);
                if numel(parts) >= 2 && parts(2) == assetName
                    expectedHash = parts(1);
                    break;
                end
            end

            if expectedHash == ""
                fprintf(2, 'No checksum found for %s in release %s.\n', assetName, tag);
                return;
            end

            fprintf('Expected SHA-256:  %s\n\n', expectedHash);

            if strcmpi(localHash, expectedHash)
                fprintf('PASS: SHA-256 checksum matches the GitHub release.\n');
            else
                fprintf(2, 'FAIL: SHA-256 mismatch!\n');
                fprintf(2, '  Local:    %s\n', localHash);
                fprintf(2, '  Expected: %s\n', expectedHash);
                fprintf(2, 'The installed binary does not match the published release.\n');
                return;
            end

            % Find or offer to download slsa-verifier.
            verifierBin = Terminal.findOrInstallSLSAVerifier();
            if isempty(verifierBin)
                return;
            end

            % Download provenance attestation and binary to a temp dir for verification.
            fprintf('\nRunning SLSA provenance verification...\n');
            tmpDir = fullfile(tempdir, 'terminal-verify');
            if isfolder(tmpDir)
                rmdir(tmpDir, 's');
            end
            mkdir(tmpDir);

            try
                provenanceURL = sprintf( ...
                    'https://github.com/%s/releases/download/%s/multiple.intoto.jsonl', ...
                    Terminal.GITHUB_REPO, tag);
                provenancePath = fullfile(tmpDir, 'multiple.intoto.jsonl');
                websave(provenancePath, provenanceURL);

                binaryURL = sprintf( ...
                    'https://github.com/%s/releases/download/%s/%s', ...
                    Terminal.GITHUB_REPO, tag, assetName);
                binaryDst = fullfile(tmpDir, assetName);
                websave(binaryDst, binaryURL);

                cmd = sprintf( ...
                    '"%s" verify-artifact --provenance-path "%s" --source-uri github.com/%s --source-tag %s "%s" 2>&1', ...
                    verifierBin, provenancePath, Terminal.GITHUB_REPO, tag, binaryDst);
                [st, output] = system(cmd);
                if st == 0
                    fprintf('PASS: SLSA provenance verification succeeded.\n');
                    fprintf('%s\n', strtrim(output));
                else
                    fprintf(2, 'FAIL: SLSA provenance verification failed.\n');
                    fprintf(2, '%s\n', strtrim(output));
                end
            catch me
                fprintf(2, 'SLSA verification error: %s\n', me.message);
            end

            % Clean up.
            try
                rmdir(tmpDir, 's');
            catch
            end
        end

        function results = test()
            %TEST Run the Terminal test suite and produce a report.
            %
            %   Terminal.test()
            %
            %   Discovers and runs all test classes in the toolbox tests/
            %   folder. Unit tests run everywhere; integration tests that
            %   need a display or server binary are skipped automatically
            %   when those resources are unavailable.
            %
            %   Produces an HTML report in a test-results/ folder and
            %   prints a summary to the command window.
            %
            %   results = Terminal.test()   — also returns the TestResult array

            testsDir = fullfile(fileparts(mfilename('fullpath')), 'tests');

            fprintf('\n<strong>Terminal Test Suite v%s</strong>\n\n', Terminal.version());

            % Discover all test classes.
            suite = matlab.unittest.TestSuite.fromFolder(testsDir);
            fprintf('Found %d tests in %s\n\n', numel(suite), testsDir);

            % Build runner with plugins.
            runner = matlab.unittest.TestRunner.withTextOutput('Verbosity', 3);

            % HTML report if available (R2020b+).
            reportDir = fullfile(pwd, 'test-results');
            try
                plugin = matlab.unittest.plugins.HTMLReportPlugin.producingReport(reportDir);
                if ~isfolder(reportDir)
                    mkdir(reportDir);
                end
                runner.addPlugin(plugin);
                hasReport = true;
            catch
                hasReport = false;
            end

            % Run.
            results = runner.run(suite);

            % Summary.
            nPassed = nnz([results.Passed]);
            nFailed = nnz([results.Failed]);
            nIncomplete = nnz([results.Incomplete]);
            nTotal = numel(results);

            fprintf('\n<strong>Results: %d/%d passed', nPassed, nTotal);
            if nFailed > 0
                fprintf(', %d failed', nFailed);
            end
            if nIncomplete > 0
                fprintf(', %d skipped', nIncomplete);
            end
            fprintf('</strong>\n');

            if hasReport
                fprintf('Report: <a href="matlab:web(''%s'',''-browser'')">%s</a>\n', ...
                    fullfile(reportDir, 'index.html'), reportDir);
            end
            fprintf('\n');

            if nargout == 0
                clear results
            end
        end
    end

    methods (Static, Access = private)
        function serverBin = setupMCP()
            %SETUPMCP Share the MATLAB session for AI agent access.
            %   Ensures the MCP Core Server Toolkit and server binary are
            %   available, calls shareMATLABSession(), and returns the
            %   server binary path for command pre-population.

            % Step 1: Ensure the toolkit is installed.
            Terminal.ensureMCPToolkit();

            % Step 2: Ensure the server binary is available.
            serverBin = Terminal.ensureMCPServerBinary();

            % Step 3: Share the session.
            try
                shareMATLABSession();
            catch me
                error('Terminal:MCPShareFailed', ...
                    'Failed to share MATLAB session:\n  %s', me.message);
            end

            fprintf('\nMATLAB session shared for AI agent access.\n');
            fprintf('The MCP registration command will be pre-populated in the terminal.\n');
            fprintf('Press Enter to register, then launch your AI agent.\n\n');
        end

        function ensureMCPToolkit()
            %ENSUREMCPTOOLKIT Check toolkit is installed; offer to install if not.
            try
                addons = matlab.addons.installedAddons;
                idx = contains(addons.Name, 'MCP Core Server', 'IgnoreCase', true);
                if any(idx)
                    return;  % Toolkit is installed.
                end
            catch
                % installedAddons not available — fall back to function check.
                if exist('shareMATLABSession', 'file') ~= 0
                    return;
                end
            end

            % Toolkit not found — offer to install.
            fprintf('%s is required for MCP=true.\n', Terminal.MCP_TOOLKIT_NAME);
            reply = input('Download and install it now? (y/n) [y]: ', 's');
            if isempty(reply), reply = 'y'; end
            if ~strcmpi(reply, 'y')
                error('Terminal:MCPToolkitNotInstalled', ...
                    ['%s is required for MCP=true.\n\n' ...
                     'Install manually from:\n  <a href="%s">%s</a>'], ...
                    Terminal.MCP_TOOLKIT_NAME, ...
                    Terminal.MCP_TOOLKIT_URL, Terminal.MCP_TOOLKIT_URL);
            end

            release = Terminal.fetchMCPRelease();
            mltbxURL = Terminal.findMCPAsset(release, '.mltbx');
            if isempty(mltbxURL)
                error('Terminal:MCPDownloadFailed', ...
                    'No .mltbx asset found in release %s.', release.tag_name);
            end

            tmpFile = fullfile(tempdir, 'MATLABMCPCoreServerToolkit.mltbx');
            fprintf('Downloading %s %s...\n', Terminal.MCP_TOOLKIT_NAME, release.tag_name);
            try
                websave(tmpFile, mltbxURL);
            catch me
                error('Terminal:MCPDownloadFailed', 'Download failed:\n  %s', me.message);
            end

            fprintf('Installing toolkit...\n');
            try
                matlab.addons.install(tmpFile);
            catch me
                delete(tmpFile);
                error('Terminal:MCPInstallFailed', 'Installation failed:\n  %s', me.message);
            end
            delete(tmpFile);
            rehash toolboxcache;
            fprintf('%s %s installed.\n\n', Terminal.MCP_TOOLKIT_NAME, release.tag_name);
        end

        function serverBin = ensureMCPServerBinary()
            %ENSUREMCPSERVERBINARY Find or download the MCP server binary.

            binaryName = Terminal.MCP_SERVER_BINARY;
            if ispc
                binaryName = [binaryName '.exe'];
            end

            % Check our managed install location first.
            installDir = fullfile(prefdir, 'matlab-mcp');
            serverBin = fullfile(installDir, binaryName);
            if isfile(serverBin)
                if Terminal.checkMCPServerVersion(serverBin)
                    return;
                end
                % Version too old — fall through to download.
            end

            % Check system PATH.
            if ispc
                [status, result] = system(sprintf('where %s 2>nul', binaryName));
            else
                [status, result] = system(sprintf('which %s 2>/dev/null', binaryName));
            end
            if status == 0
                found = strtrim(result);
                % Take only the first line (where may return multiple).
                lines = splitlines(found);
                found = lines{1};
                if Terminal.checkMCPServerVersion(found)
                    serverBin = found;
                    return;
                end
                % Version too old — fall through to download.
            end

            % Not found — offer to download.
            fprintf('MCP server binary not found on PATH or in %s.\n', installDir);
            fprintf('  Default install location: %s\n\n', serverBin);
            reply = input('Download it now? (y/n) [y]: ', 's');
            if isempty(reply), reply = 'y'; end
            if ~strcmpi(reply, 'y')
                % Ask for an existing path instead.
                customPath = input('Enter path to existing matlab-mcp-core-server binary (or empty to cancel): ', 's');
                customPath = strtrim(customPath);
                if ~isempty(customPath) && isfile(customPath)
                    serverBin = customPath;
                    return;
                end
                error('Terminal:MCPBinaryNotFound', ...
                    ['MCP server binary is required for MCP=true.\n\n' ...
                     'Download from:\n  <a href="%s">%s</a>'], ...
                    Terminal.MCP_TOOLKIT_URL, Terminal.MCP_TOOLKIT_URL);
            end

            % Determine platform asset name.
            arch = computer('arch');
            switch arch
                case 'glnxa64', assetSuffix = '-glnxa64';
                case 'maca64',  assetSuffix = '-maca64';
                case 'maci64',  assetSuffix = '-maci64';
                case 'win64',   assetSuffix = '-win64.exe';
                otherwise
                    error('Terminal:MCPUnsupportedPlatform', ...
                        'Unsupported platform: %s', arch);
            end

            release = Terminal.fetchMCPRelease();
            assetName = [Terminal.MCP_SERVER_BINARY assetSuffix];
            binaryURL = Terminal.findMCPAsset(release, assetName);
            if isempty(binaryURL)
                error('Terminal:MCPDownloadFailed', ...
                    'No binary asset "%s" found in release %s.', assetName, release.tag_name);
            end

            % Download.
            if ~isfolder(installDir)
                mkdir(installDir);
            end
            fprintf('Downloading %s %s for %s...\n', ...
                Terminal.MCP_SERVER_BINARY, release.tag_name, arch);
            try
                websave(serverBin, binaryURL);
            catch me
                error('Terminal:MCPDownloadFailed', 'Download failed:\n  %s', me.message);
            end

            % Make executable and strip quarantine on macOS.
            if ~ispc
                system(sprintf('chmod +x "%s"', serverBin));
                if ismac
                    system(sprintf('xattr -d com.apple.quarantine "%s" 2>/dev/null', serverBin));
                end
            end
            fprintf('MCP server binary installed at:\n  %s\n\n', serverBin);
        end

        function ok = checkMCPServerVersion(serverBin)
            %CHECKMCPSERVERVERSION Check binary meets minimum version.
            %   Returns true if the version is acceptable, false if too old.
            %   Fragile: assumes --version outputs a semver-like string.
            ok = false;
            try
                [status, output] = system(sprintf('"%s" --version', serverBin));
                if status ~= 0
                    warning('Terminal:MCPVersionCheckFailed', ...
                        'Could not determine MCP server version. Proceeding anyway.');
                    ok = true;  % Don't block on version check failure.
                    return;
                end
                % Parse version from output (e.g., "matlab-mcp-core-server v0.8.1" or "0.8.1").
                tokens = regexp(strtrim(output), '(\d+\.\d+\.\d+)', 'tokens', 'once');
                if isempty(tokens)
                    warning('Terminal:MCPVersionCheckFailed', ...
                        'Could not parse MCP server version from: %s', strtrim(output));
                    ok = true;
                    return;
                end
                ver = tokens{1};
                if Terminal.compareVersions(ver, Terminal.MCP_MIN_SERVER_VERSION) >= 0
                    ok = true;
                else
                    fprintf('MCP server binary at "%s" is version %s.\n', serverBin, ver);
                    fprintf('Minimum required version is %s.\n\n', Terminal.MCP_MIN_SERVER_VERSION);
                end
            catch
                ok = true;  % Don't block on unexpected errors.
            end
        end

        function result = compareVersions(a, b)
            %COMPAREVERSIONS Compare two semver strings. Returns -1, 0, or 1.
            partsA = sscanf(a, '%d.%d.%d')';
            partsB = sscanf(b, '%d.%d.%d')';
            for i = 1:3
                if partsA(i) < partsB(i), result = -1; return; end
                if partsA(i) > partsB(i), result =  1; return; end
            end
            result = 0;
        end

        function release = fetchMCPRelease()
            %FETCHMCPRELEASE Fetch the latest MCP Core Server release from GitHub.
            persistent cachedRelease
            if ~isempty(cachedRelease)
                release = cachedRelease;
                return;
            end
            try
                opts = weboptions('ContentType', 'json', 'Timeout', 10);
                release = webread(Terminal.MCP_GITHUB_API, opts);
                cachedRelease = release;
            catch me
                error('Terminal:MCPDownloadFailed', ...
                    ['Could not reach GitHub to check for the MCP Core Server.\n' ...
                     '  %s\n\nInstall manually from:\n  <a href="%s">%s</a>'], ...
                    me.message, Terminal.MCP_TOOLKIT_URL, Terminal.MCP_TOOLKIT_URL);
            end
        end

        function url = findMCPAsset(release, namePattern)
            %FINDMCPASSET Find a release asset URL by name pattern.
            url = '';
            for i = 1:numel(release.assets)
                if endsWith(release.assets(i).name, namePattern)
                    url = release.assets(i).browser_download_url;
                    return;
                end
            end
        end

        function result = registry(action, obj)
            %REGISTRY Persistent store for tracking Terminal instances.
            persistent instances
            if isempty(instances)
                instances = Terminal.empty;
            end
            switch action
                case 'add'
                    instances(end+1) = obj;
                case 'remove'
                    instances(instances == obj) = [];
                case 'get'
                    % Prune deleted handles before returning.
                    instances(~isvalid(instances)) = [];
                    result = instances;
                    return;
            end
            result = Terminal.empty;
        end

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

            % Strip macOS quarantine attribute from all extracted files.
            % Downloaded .mltbx files inherit com.apple.quarantine, which
            % causes Gatekeeper to block the unsigned server binary.
            % Use -cr (clear, recursive) to silently handle files that
            % don't have the attribute.
            if ismac
                [~, ~] = system(sprintf('xattr -cr "%s"', cacheRoot));
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

        function alive = isProcessAlive(pid)
            %ISPROCESSALIVE Check if a process is still running (cross-platform).
            if ispc
                [st, ~] = system(sprintf('tasklist /FI "PID eq %d" /NH 2>nul | findstr /R "^[0-9]" >nul 2>&1', pid));
            else
                [st, ~] = system(sprintf('kill -0 %d 2>/dev/null', pid));
            end
            alive = (st == 0);
        end

        function verifierBin = findOrInstallSLSAVerifier()
            %FINDORINSTALLSLSAVERIFIER Locate slsa-verifier or offer to download it.
            %   Returns the path to the binary, or '' if unavailable.
            binaryName = 'slsa-verifier';
            if ispc
                binaryName = [binaryName '.exe'];
            end

            % Check managed install location first.
            installDir = fullfile(prefdir, 'matlab-terminal', 'bin');
            candidate = fullfile(installDir, binaryName);
            if isfile(candidate)
                verifierBin = candidate;
                return;
            end

            % Check system PATH.
            if ispc
                [st, result] = system(sprintf('where %s 2>nul', binaryName));
            else
                [st, result] = system(sprintf('which %s 2>/dev/null', binaryName));
            end
            if st == 0
                verifierBin = strtrim(splitlines(string(result)));
                verifierBin = char(verifierBin(1));
                return;
            end

            % Not found — offer to download.
            arch = computer('arch');
            switch arch
                case 'glnxa64', assetPattern = 'linux-amd64';
                case 'maci64',  assetPattern = 'darwin-amd64';
                case 'maca64',  assetPattern = 'darwin-arm64';
                case 'win64',   assetPattern = 'windows-amd64.exe';
                otherwise
                    fprintf(2, 'Unsupported platform: %s\n', arch);
                    verifierBin = '';
                    return;
            end

            fprintf('\nslsa-verifier not found on PATH or in %s.\n', installDir);
            fprintf('  Source:      https://github.com/slsa-framework/slsa-verifier/releases\n');
            fprintf('  Install to:  %s\n\n', candidate);
            reply = input('Download slsa-verifier for SLSA provenance verification? (y/n) [y]: ', 's');
            if isempty(reply), reply = 'y'; end
            if ~strcmpi(reply, 'y')
                fprintf('Skipping SLSA provenance check.\n');
                verifierBin = '';
                return;
            end

            % Fetch latest release from slsa-verifier repo.
            try
                opts = weboptions('ContentType', 'json', 'Timeout', 10);
                release = webread( ...
                    'https://api.github.com/repos/slsa-framework/slsa-verifier/releases/latest', opts);
            catch me
                fprintf(2, 'Could not fetch slsa-verifier release: %s\n', me.message);
                verifierBin = '';
                return;
            end

            % Find the matching asset.
            downloadURL = '';
            for i = 1:numel(release.assets)
                name = string(release.assets(i).name);
                if contains(name, assetPattern) && ~contains(name, '.sig') && ~contains(name, '.pem') && ~contains(name, '.intoto')
                    downloadURL = release.assets(i).browser_download_url;
                    break;
                end
            end
            if downloadURL == ""
                fprintf(2, 'No slsa-verifier binary found for %s.\n', arch);
                verifierBin = '';
                return;
            end

            % Download.
            if ~isfolder(installDir)
                mkdir(installDir);
            end
            fprintf('Downloading slsa-verifier %s...\n', release.tag_name);
            try
                websave(candidate, downloadURL);
            catch me
                fprintf(2, 'Download failed: %s\n', me.message);
                verifierBin = '';
                return;
            end

            if ~ispc
                system(sprintf('chmod +x "%s"', candidate));
                if ismac
                    system(sprintf('xattr -d com.apple.quarantine "%s" 2>/dev/null', candidate));
                end
            end
            fprintf('Installed slsa-verifier at:\n  %s\n', candidate);
            verifierBin = candidate;
        end

        function release = fetchLatestRelease()
            %FETCHLATESTRELEASE Fetch the latest stable release from GitHub.
            %   Uses the /releases/latest endpoint, which excludes
            %   pre-releases and drafts.
            url = sprintf('https://api.github.com/repos/%s/releases/latest', ...
                Terminal.GITHUB_REPO);
            try
                opts = weboptions('ContentType', 'json', 'Timeout', 10);
                release = webread(url, opts);
            catch me
                error('Terminal:UpdateFailed', ...
                    'Could not reach GitHub:\n  %s', me.message);
            end
        end

        function release = fetchRelease(version)
            %FETCHRELEASE Fetch a specific release by version tag.
            version = string(version);
            if ~startsWith(version, 'v')
                tag = "v" + version;
            else
                tag = version;
            end
            url = sprintf('https://api.github.com/repos/%s/releases/tags/%s', ...
                Terminal.GITHUB_REPO, tag);
            try
                opts = weboptions('ContentType', 'json', 'Timeout', 10);
                release = webread(url, opts);
            catch me
                error('Terminal:UpdateFailed', ...
                    'Release "%s" not found on GitHub:\n  %s', tag, me.message);
            end
        end

        function v = tagToVersion(tag)
            %TAGTOVERSION Strip leading "v" from a tag name.
            v = string(tag);
            if startsWith(v, 'v')
                v = extractAfter(v, 1);
            end
        end

        function mltbxURL = findMltbxAsset(release)
            %FINDMLTBXASSET Find the .mltbx download URL in a release.
            mltbxURL = '';
            assets = release.assets;
            for i = 1:numel(assets)
                if iscell(assets)
                    asset = assets{i};
                else
                    asset = assets(i);
                end
                if endsWith(asset.name, '.mltbx')
                    mltbxURL = asset.browser_download_url;
                    break;
                end
            end
            if isempty(mltbxURL)
                v = Terminal.tagToVersion(release.tag_name);
                error('Terminal:UpdateFailed', ...
                    'No .mltbx file found in release %s.', v);
            end
        end

        function token = generateToken()
            %GENERATETOKEN Generate a 32-char hex auth token.
            %   Uses /dev/urandom (Unix) or PowerShell (Windows) for
            %   cryptographic randomness, falling back to randi if needed.
            token = '';
            try
                if ispc
                    [status, token] = system('powershell -c "[guid]::NewGuid().ToString(''N'')"');
                    if status == 0
                        token = strtrim(token);
                    else
                        token = '';
                    end
                else
                    fid = fopen('/dev/urandom', 'r');
                    if fid ~= -1
                        bytes = fread(fid, 16, '*uint8');
                        fclose(fid);
                        token = sprintf('%02x', bytes);
                    end
                end
            catch
            end
            if strlength(token) ~= 32
                token = sprintf('%04x', randi(65535, 1, 8));
            end
        end

        function hash = sha256file(filepath)
            %SHA256FILE Compute the SHA-256 hex digest of a file.
            if ispc
                [st, out] = system(sprintf('certutil -hashfile "%s" SHA256', filepath));
                if st == 0
                    lines = splitlines(strtrim(out));
                    % certutil outputs: header, hash, footer
                    hash = strtrim(strrep(lines{2}, ' ', ''));
                    return;
                end
            else
                [st, out] = system(sprintf('sha256sum "%s"', filepath));
                if st == 0
                    parts = split(strtrim(out));
                    hash = char(parts(1));
                    return;
                end
            end
            error('Terminal:HashFailed', ...
                'Could not compute SHA-256 hash for:\n  %s', filepath);
        end

    end
end
