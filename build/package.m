% Copyright 2026 The MathWorks, Inc.

% package.m — Build the Terminal.mltbx toolbox package.
%
% Run from the matlab-terminal project root:
%   >> run('build/package.m')

projectDir = fileparts(fileparts(mfilename('fullpath')));
toolboxDir = fullfile(projectDir, 'toolbox');
distDir = fullfile(projectDir, 'dist');
if ~isfolder(distDir)
    mkdir(distDir);
end
outputFile = fullfile(distDir, 'Terminal.mltbx');

% --- Step 1: Bundle web assets into .mat ---
% packageToolbox silently drops .html/.css/.js files, so we embed them
% in a .mat file that Terminal.m extracts at runtime.
run(fullfile(projectDir, 'build', 'build_assets.m'));

% --- Step 2: Build .mltbx ---
opts = matlab.addons.toolbox.ToolboxOptions(toolboxDir, ...
    '9e8f4a2b-3c1d-4e5f-a6b7-8c9d0e1f2a3b');

opts.ToolboxName = 'MATLAB Terminal';
opts.ToolboxVersion = '0.1.0';
opts.Summary = 'Embedded system terminal for MATLAB';
opts.Description = ['Run system commands, git, docker, and CLI tools ' ...
    'directly inside the MATLAB Desktop. ' ...
    'Supports multiple tabs, MATLAB theme integration, ' ...
    'and docked or floating windows.'];
opts.AuthorName = 'The MathWorks, Inc.';
opts.AuthorEmail = 'support@mathworks.com';
opts.MinimumMatlabRelease = '';  % TBD — see README for feature constraints
opts.MaximumMatlabRelease = '';
opts.ToolboxMatlabPath = toolboxDir;
opts.AppGalleryFiles = fullfile(toolboxDir, 'openTerminal.m');
opts.OutputFile = outputFile;

matlab.addons.toolbox.packageToolbox(opts);
fprintf('Packaged: %s\n', outputFile);
