%[text] # Install Terminal in MATLAB
%[text] This script downloads and installs the latest release of Terminal from GitHub.
%[text] ## What to expect:
%[text] - If Terminal is already installed, the current version is shown and you are asked whether to continue. Press Enter to proceed or type "n" to cancel.
%[text] - The script downloads Terminal.mltbx from the latest GitHub release.
%[text] - Any existing Terminal installation is uninstalled first.
%[text] - The downloaded toolbox is installed using matlab.addons.install.
%[text] - The temporary .mltbx file is deleted after installation.
%[text] - A Terminal window opens so you can start using it right away. \
%[text] ## Requirements:
%[text] - Internet access (to reach github.com)
%[text] - MATLAB R2024b or later \
%%
%[text] ## Check for an existing installation
addons = matlab.addons.installedAddons;
terminalAddon = addons(addons.Name == "Terminal", :);
if ~isempty(terminalAddon) %[output:group:6433bcaf]
    disp("Terminal " + terminalAddon.Version + " is already installed."); %[output:8d2d015c]
    reply = input("Re-install with the latest version? [Y/n]: ", "s");
    if strtrim(lower(reply)) == "n"
        disp("Installation cancelled.");
        return
    end
    disp("Uninstalling Terminal " + terminalAddon.Version + "..."); %[output:2a07cfc2]
    matlab.addons.uninstall("Terminal");
end %[output:group:6433bcaf]
%%
%[text] ## Download the latest release
url = "https://github.com/prabhakk-mw/matlab-terminal/releases/latest/download/Terminal.mltbx";
mltbxFile = fullfile(tempdir, "Terminal.mltbx");

disp("Downloading Terminal.mltbx from GitHub..."); %[output:8b32af35]
websave(mltbxFile, url);

disp("Download complete."); %[output:6dc9bd10]

disp("Installing Terminal..."); %[output:60ebb475]
matlab.addons.install(mltbxFile);
delete(mltbxFile);
disp("Terminal " + Terminal.version() + " installed successfully."); %[output:94338645]
%%
%[text] ## Open a Terminal
edit(fullfile(fileparts(which("Terminal.m")), "doc","GettingStarted.mlx"))
cd(userpath)
Terminal(); %[output:2d5a62c8]

%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"inline","rightPanelPercent":42.5}
%---
%[output:8d2d015c]
%   data: {"dataType":"text","outputData":{"text":"Terminal 0.13.2 is already installed.\n","truncated":false}}
%---
%[output:2a07cfc2]
%   data: {"dataType":"text","outputData":{"text":"Uninstalling Terminal 0.13.2...\n","truncated":false}}
%---
%[output:8b32af35]
%   data: {"dataType":"text","outputData":{"text":"Downloading Terminal.mltbx from GitHub...\n","truncated":false}}
%---
%[output:6dc9bd10]
%   data: {"dataType":"text","outputData":{"text":"Download complete.\n","truncated":false}}
%---
%[output:60ebb475]
%   data: {"dataType":"text","outputData":{"text":"Installing Terminal...\n","truncated":false}}
%---
%[output:94338645]
%   data: {"dataType":"text","outputData":{"text":"Terminal 0.13.2 installed successfully.\n","truncated":false}}
%---
%[output:2d5a62c8]
%   data: {"dataType":"text","outputData":{"text":"Extracting Terminal assets to:\n  \/tmp\/MATLAB Add-Ons\/Toolboxes\/Terminal\n","truncated":false}}
%---
