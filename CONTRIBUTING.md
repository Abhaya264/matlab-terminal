# Contributing to MATLAB Terminal

Thank you for your interest in contributing! This guide covers everything you need to get started.

## Prerequisites

- **Go 1.21+** — Download from [go.dev/dl](https://go.dev/dl/) or use your package manager
- **MATLAB** — Required for running and packaging the toolbox (minimum release TBD, see README)
- **Git**

Verify your Go installation:

```bash
go version
```

## Getting the Source

1. Fork the repository on GitHub.

2. Clone your fork:
   ```bash
   git clone https://github.com/<your-username>/matlab-terminal.git
   cd matlab-terminal
   ```

3. Add the upstream remote:
   ```bash
   git remote add upstream https://github.com/mathworks/matlab-terminal.git
   ```

## Building

### Go server

```bash
cd server/
```

Build for your platform into `dist/<arch>/`:

| Platform | Build command |
|----------|---------------|
| Linux x86_64 | `mkdir -p ../dist/glnxa64 && go build -ldflags "-s -w" -o ../dist/glnxa64/matlab-terminal-server .` |
| macOS Intel | `mkdir -p ../dist/maci64 && GOARCH=amd64 go build -ldflags "-s -w" -o ../dist/maci64/matlab-terminal-server .` |
| macOS Apple Silicon | `mkdir -p ../dist/maca64 && GOARCH=arm64 go build -ldflags "-s -w" -o ../dist/maca64/matlab-terminal-server .` |
| Windows x86_64 | `mkdir -p ../dist/win64 && GOOS=windows GOARCH=amd64 go build -ldflags "-s -w" -o ../dist/win64/matlab-terminal-server.exe .` |

The `-ldflags "-s -w"` flag strips debug symbols to reduce size.

### Toolbox package

From MATLAB, in the project root:

```matlab
addpath('build')
package()             % dev build (version from TerminalVersion.m)
package("1.2.0")      % release build with explicit version
```

This bundles web assets and the Go binary into `dist/Terminal.mltbx`.

## Running from Source

No packaging needed during development:

```bash
# 1. Build the server (example for Linux)
cd server && mkdir -p ../dist/glnxa64 && go build -o ../dist/glnxa64/matlab-terminal-server . && cd ..
```

```matlab
% 2. Add toolbox to path and launch
addpath('toolbox')
Terminal()
```

## Project Structure

```
toolbox/                            Toolbox source (shipped in .mltbx)
  Terminal.m                        Main MATLAB class
  TerminalVersion.m                 Version string (stamped at build time)
  openTerminal.m                    Launcher for Apps tab
  doc/                              Documentation
    GettingStarted.m                Getting Started guide (shown on install)
  images/                           Toolbox icon
    matlab-terminal.jpeg
  html/                             Web frontend (xterm.js, inline JS)
    index.html                      Terminal UI
    terminal.css                    Styles
    lib/xterm/                      Vendored xterm.js + fit addon
server/                             Go server source
  main.go                           Entry point, CLI flags, HTTP routes
  api.go                            HTTP API handlers
  session.go                        PTY session lifecycle
  pty.go                            Platform-agnostic PTY interface
  pty_unix.go                       Unix PTY (creack/pty)
  pty_windows.go                    Windows PTY (ConPTY)
  shell_unix.go                     Default shell detection (Unix)
  shell_windows.go                  Default shell detection (Windows)
  auth.go                           Token validation middleware
build/                              Build tooling (not shipped)
  build_assets.m                    Bundles web assets + binary into .mat
  package.m                         Builds .mltbx (function, accepts version arg)
  setup_xterm.sh                    Downloads and vendors xterm.js
dist/                               Build output (gitignored)
```

## Making Changes

1. Create a branch from `main`:
   ```bash
   git checkout -b my-feature
   ```

2. Make your changes. Keep commits focused — one logical change per commit.

3. Run the checks locally before pushing:
   ```bash
   cd server
   go vet ./...
   go build ./...
   go test -race ./...
   ```

4. Test in MATLAB:
   ```matlab
   addpath('toolbox')
   t = Terminal();
   % exercise your changes
   delete(t);
   ```

5. Push and open a pull request against `main`:
   ```bash
   git push origin my-feature
   ```

## Code Style

### Go
- Follow standard Go conventions. Run `go vet` and `gofmt`.
- Keep functions short and focused.

### MATLAB
- Follow MATLAB naming conventions (camelCase for functions, PascalCase for classes).
- Use `arguments` blocks for input validation where appropriate.

### All files
- All new source files must include the copyright header as the first line:
  ```go
  // Copyright 2026 The MathWorks, Inc.
  ```
  ```matlab
  % Copyright 2026 The MathWorks, Inc.
  ```
  Use the current year. For files modified in a later year, update to a range (e.g., `2026-2027`).

## Updating Vendored Dependencies

xterm.js and its fit addon are vendored in `toolbox/html/lib/xterm/`. To update:

```bash
cd toolbox/html
bash ../../build/setup_xterm.sh
```

## Testing

### Go server
```bash
cd server
go test ./...
go test -race ./...
```

### End-to-end
Currently manual — launch `Terminal()` in MATLAB and verify:
- Terminal renders and accepts input
- Multiple tabs work
- Resize behaves correctly
- `exit` closes the tab
- Closing the last tab closes the window

## Reporting Issues

Open an issue on GitHub with:
- What you expected to happen
- What actually happened
- Steps to reproduce
- MATLAB version and OS
- Any error messages from the MATLAB Command Window

---

Copyright 2026 The MathWorks, Inc.
