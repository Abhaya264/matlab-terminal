% Copyright 2026 The MathWorks, Inc.

% build_assets.m — Bundle web assets and server binary into a .mat.
%
% Run from the matlab-terminal project root:
%   >> run('build/build_assets.m')
%
% This creates toolbox/web_assets.mat containing all files that
% packageToolbox silently drops (.html, .css, .js, binaries).

projectDir = fileparts(fileparts(mfilename('fullpath')));
toolboxDir = fullfile(projectDir, 'toolbox');

files = {
    'html/index.html'
    'html/terminal.css'
    'html/lib/xterm/xterm.js'
    'html/lib/xterm/xterm.css'
    'html/lib/xterm/addon-fit.js'
};

% Add the server binary for the current platform.
arch = computer('arch');
binaryName = 'matlab-terminal-server';
if strcmp(arch, 'win64')
    binaryName = [binaryName, '.exe'];
end
binaryPath = fullfile(projectDir, 'dist', binaryName);
if isfile(binaryPath)
    files{end+1} = ['bin/', arch, '/', binaryName];
else
    warning('build_assets:NoBinary', ...
        'Server binary not found at:\n  %s\nSkipping.', binaryPath);
end

assets = struct();
for i = 1:numel(files)
    rel = files{i};
    % Resolve source path: bin/ files come from server/, others from toolbox/.
    if startsWith(rel, 'bin/')
        src = binaryPath;
    else
        src = fullfile(toolboxDir, rel);
    end
    % Use fread for binary-safe reading.
    fid = fopen(src, 'r');
    data = fread(fid, '*uint8');
    fclose(fid);
    key = regexprep(rel, '[/.\\-]', '_');
    assets.(key) = struct('path', rel, 'data', data, 'executable', startsWith(rel, 'bin/'));
    fprintf('  packed: %s (%d bytes)\n', rel, numel(data));
end

outFile = fullfile(toolboxDir, 'web_assets.mat');
save(outFile, 'assets', '-v7.3');
fprintf('Saved: %s\n', outFile);
