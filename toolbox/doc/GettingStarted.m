%% Getting Started with Terminal
% Terminal embeds a full system terminal inside the MATLAB Desktop.
% Run shell commands, git, docker, and CLI tools without leaving MATLAB.

%% Opening a Terminal
% Create a docked terminal with one line:

t = Terminal();

%% Named Terminals
% Give each terminal a descriptive name so you can tell them apart in
% the MATLAB Desktop tab bar.

t1 = Terminal(Name="Build");
t2 = Terminal(Name="Git");

%% Floating Windows
% Open a terminal in its own undocked window instead of the desktop.

t = Terminal(WindowStyle="normal");

%% Custom Shell
% By default the terminal uses your system shell ($SHELL on Unix,
% %COMSPEC% on Windows). Override it with the Shell argument.

% Linux/macOS examples:
t = Terminal(Shell="zsh");
t = Terminal(Shell="/bin/bash");

% Windows examples:
% t = Terminal(Shell="powershell.exe");
% t = Terminal(Shell="wsl.exe");

%% Embedding in an Existing Figure
% Pass a figure or panel as the first argument to embed a terminal
% inside your own UI layout.

fig = uifigure("Name", "My App");
t = Terminal(fig);

%% Managing Running Terminals
% List all open terminals and close them programmatically.

terminals = Terminal.list();    % returns handles to all running terminals
Terminal.closeAll();            % closes every terminal

%% Checking the Version
% Display the installed toolbox version:

Terminal.version()

%% Updating
% Check for a newer release on GitHub and update interactively:

Terminal.update()

%% Cleaning Up
% Close a single terminal by deleting its handle. The server process
% and figure window are cleaned up automatically.

t = Terminal();
% ... use the terminal ...
delete(t);

%% Next Steps
%
% * Type |help Terminal| at the command prompt for full API documentation.
% * Visit the project repository for source code and issue tracking.
