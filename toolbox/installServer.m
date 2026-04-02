% Copyright 2026 The MathWorks, Inc.

function installServer()
    %INSTALLSERVER Download the matlab-terminal-server binary for this platform.
    %
    %   installServer()
    %
    %   This is a convenience wrapper around Terminal.install(). It downloads
    %   the correct server binary for the current OS/architecture and places
    %   it in <userpath>/bin/.
    %
    %   See also: Terminal.install, Terminal.update

    Terminal.install();
end
