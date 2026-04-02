# MATLAB Terminal

Embedded system terminal for MATLAB Desktop. Run CLI tools, git, docker, AI coding agents, and more — without leaving MATLAB.

## Why?

MATLAB is great for computation, but modern development workflows often require tools that live outside MATLAB: version control, containers, package managers, cloud CLIs, and AI coding agents. Switching between MATLAB and a separate terminal window breaks focus and adds friction.

MATLAB Terminal brings the system shell directly into the MATLAB Desktop, so you can:

- **Use AI coding agents** — Run Claude Code, GitHub Copilot CLI, or Aider side-by-side with your MATLAB editor
- **Manage source control** — `git commit`, `git push`, resolve merge conflicts, review diffs — all without leaving MATLAB
- **Run containers and services** — `docker build`, `docker compose up`, monitor logs in a docked panel
- **Install packages** — `pip install`, `conda`, `npm`, `apt-get` for polyglot projects that mix MATLAB with Python, JavaScript, or C
- **Connect to remote systems** — `ssh` into HPC clusters, cloud VMs, or lab machines
- **Run build tools** — `make`, `cmake`, CI/CD scripts, test runners
- **Monitor system resources** — `htop`, `top`, `nvidia-smi` for GPU workloads
- **Edit config files** — Quick `vim` or `nano` edits without opening another app

## Features

- **Full terminal emulator** — PTY-based with 256-color support, cursor movement, and escape sequences. Interactive tools like vim, htop, and ssh work correctly.
- **Tabbed interface** — Open multiple terminal sessions in a single panel. Create, close, and switch tabs.
- **Docked in MATLAB Desktop** — The terminal panel docks into the MATLAB layout like any other tool window. Undock to a floating window with `WindowStyle="normal"`.
- **MATLAB theme integration** — Automatically inherits your MATLAB theme (light or dark), code font family, and font size.
- **Copy and paste** — Ctrl+Shift+C to copy selection, Ctrl+Shift+V to paste.
- **Auto-cleanup** — Closing the last tab closes the window. The server process is killed when the terminal is deleted or MATLAB exits. Idle timeout as a safety net.
- **MATLAB environment variables** — Terminal sessions have `MATLAB_PID` and `MATLAB_ROOT` set, allowing CLI tools to discover the running MATLAB instance.
- **Loading screen** — Shows keyboard shortcuts while the terminal initializes.
- **matlab-proxy compatible** — Works in browser-based MATLAB via [matlab-proxy](https://github.com/mathworks/matlab-proxy).
- **Zero runtime dependencies** — No Node.js, Python, or Java required. A single Go binary handles all PTY management.

## User Guide

### Installation

Download `Terminal.mltbx` from the [latest release](../../releases/latest) and install in MATLAB:

```matlab
matlab.addons.toolbox.installToolbox('Terminal.mltbx')
```

On first launch, bundled assets are automatically extracted to a local cache. No additional setup is required.

### Usage

```matlab
% Open a docked terminal
t = Terminal();

% Open with a custom title
t = Terminal(Name="Build");

% Open in a floating window
t = Terminal(WindowStyle="normal");

% Close the terminal
delete(t);
```

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Ctrl+Shift+C | Copy selection |
| Ctrl+Shift+V | Paste |
| `exit` | Close current terminal tab |

### Requirements

- MATLAB (minimum supported release TBD — see below)
- Linux (macOS and Windows support planned)

The exact minimum MATLAB release is yet to be determined. The following features constrain it:

| Feature | Minimum Release |
|---------|----------------|
| `uihtml` | R2019b |
| `arguments` blocks | R2019b |
| `uifigure` `WindowStyle='modal'` | R2020b |
| `uifigure` `WindowStyle='docked'` | TBD |
| `settings().matlab.editor.colortheme` | TBD |
| `matlab.addons.toolbox.ToolboxOptions` (build-time only) | R2022a |

### Uninstalling

```matlab
matlab.addons.uninstall('MATLAB Terminal')
```

---

## Developer Guide

### Repository Structure

```
matlab-terminal/
├── toolbox/                        # Toolbox source (becomes .mltbx content)
│   ├── Terminal.m                  # Main MATLAB class
│   ├── openTerminal.m              # Launcher for Apps tab
│   ├── installServer.m             # Convenience wrapper for Terminal.install()
│   ├── checksums.json              # SHA-256 hashes for manual binary download
│   └── html/                       # Web frontend
│       ├── index.html              # Terminal UI (all JS inline, uihtml requirement)
│       ├── terminal.css            # Tab bar, theme, loading overlay styles
│       └── lib/xterm/              # Vendored xterm.js + fit addon
├── server/                         # Go server source
│   ├── main.go                     # Entry point, CLI flags, HTTP routes
│   ├── api.go                      # HTTP API handlers (create, input, resize, poll)
│   ├── session.go                  # PTY session lifecycle
│   ├── auth.go                     # Token validation middleware
│   └── go.mod / go.sum             # Go dependencies
├── build/                          # Build tooling (not shipped in .mltbx)
│   ├── build_assets.m              # Bundles web assets + binary into .mat
│   ├── package.m                   # Builds .mltbx (calls build_assets.m)
│   └── setup_xterm.sh              # Downloads and vendors xterm.js
├── dist/                           # Build output (gitignored)
│   ├── matlab-terminal-server      # Compiled Go binary
│   └── Terminal.mltbx              # Installable toolbox package
├── DESIGN.md                       # Architecture decisions and security analysis
└── README.md
```

### Architecture

```
MATLAB (Terminal.m)  ←— Data channel —→  uihtml (xterm.js)
        │
        │  HTTP polling (100ms)
        ▼
Go server (matlab-terminal-server)  ←→  PTY sessions
```

- **Frontend**: xterm.js in MATLAB's `uihtml`. All JS is inline (uihtml sandboxes external scripts).
- **Backend**: Go binary managing PTY sessions over a localhost HTTP API with token auth.
- **Bridge**: MATLAB polls the server and relays output to JS. JS input is queued and sent through MATLAB.

See [DESIGN.md](DESIGN.md) for detailed architecture decisions and security analysis.

### Development Setup

1. **Build the Go server** (requires Go 1.21+):
   ```bash
   cd server/
   go build -o ../dist/matlab-terminal-server .
   ```

2. **Add the toolbox to your MATLAB path**:
   ```matlab
   addpath('/path/to/matlab-terminal/toolbox')
   ```

3. **Launch**:
   ```matlab
   Terminal()
   ```

When running from source, `Terminal.m` uses `html/` directly and finds the server binary via `$PATH` — no `.mat` extraction needed.

### Building a Release

The release artifact is a single file: **`Terminal.mltbx`**. It bundles the MATLAB code, web frontend, and the platform-specific Go binary into a self-contained installable package.

#### Local build

Requires MATLAB and a compiled Go binary in `dist/`.

```matlab
cd /path/to/matlab-terminal

% This runs build_assets.m (packs HTML + binary into .mat) then packageToolbox.
run('build/package.m')
```

Output: `dist/Terminal.mltbx`

#### What `package.m` does

1. **`build_assets.m`** — Reads `html/` files and `dist/matlab-terminal-server`, packs them as byte arrays into `toolbox/web_assets.mat`. This works around `packageToolbox` silently dropping `.html`, `.css`, `.js`, and binary files.
2. **`packageToolbox`** — Creates the `.mltbx` from `toolbox/`, which now includes the `.mat` alongside the `.m` files.

At runtime, `Terminal.m` extracts assets from `web_assets.mat` to `prefdir/matlab-terminal/` on first launch (version-stamped to avoid re-extraction).

### CI/CD Pipeline (GitHub Actions)

A release build involves two stages: compiling the Go binary, then packaging the `.mltbx`.

```yaml
# .github/workflows/release.yml (outline)
name: Release
on:
  push:
    tags: ['v*']

jobs:
  build-server:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: '1.21'
      - run: |
          cd server
          GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o ../dist/matlab-terminal-server .
      - uses: actions/upload-artifact@v4
        with:
          name: server-binary
          path: dist/matlab-terminal-server

  build-mltbx:
    needs: build-server
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with:
          name: server-binary
          path: dist/
      - run: chmod +x dist/matlab-terminal-server
      - uses: matlab-actions/setup-matlab@v2
      - uses: matlab-actions/run-command@v2
        with:
          command: run('build/package.m')
      - uses: actions/upload-artifact@v4
        with:
          name: Terminal.mltbx
          path: dist/Terminal.mltbx

  release:
    needs: build-mltbx
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: Terminal.mltbx
      - uses: softprops/action-gh-release@v2
        with:
          files: Terminal.mltbx
```

> **Note**: The `matlab-actions/setup-matlab` action requires a [MATLAB license](https://github.com/matlab-actions/setup-matlab#use-matlab-batch-licensing-token). For public repositories, MathWorks provides free CI licenses via [MATLAB batch licensing tokens](https://www.mathworks.com/help/cloudcenter/ug/matlab-batch-licensing-tokens.html).

#### Multi-platform builds

Currently, `build_assets.m` bundles the binary for the current platform only. To support multiple platforms, the CI pipeline would:

1. Cross-compile Go binaries for each target (`linux/amd64`, `darwin/amd64`, `darwin/arm64`, `windows/amd64`)
2. Either produce a separate `.mltbx` per platform, or modify `build_assets.m` to embed all binaries and have `Terminal.m` extract the correct one at runtime based on `computer('arch')`

### Cross-Compiling the Go Server

```bash
cd server/

# Linux (amd64)
GOOS=linux  GOARCH=amd64 go build -ldflags="-s -w" -o ../dist/matlab-terminal-server-linux-amd64 .

# macOS (Intel)
GOOS=darwin GOARCH=amd64 go build -ldflags="-s -w" -o ../dist/matlab-terminal-server-darwin-amd64 .

# macOS (Apple Silicon)
GOOS=darwin GOARCH=arm64 go build -ldflags="-s -w" -o ../dist/matlab-terminal-server-darwin-arm64 .

# Windows
GOOS=windows GOARCH=amd64 go build -ldflags="-s -w" -o ../dist/matlab-terminal-server-windows-amd64.exe .
```

The `-ldflags="-s -w"` flag strips debug symbols, reducing binary size by ~30%.

## Known Limitations and Roadmap

### Not yet implemented
- **macOS and Windows support** — The Go server compiles cross-platform, but PTY handling and binary packaging have only been tested on Linux.
- **Configurable shell** — Currently uses `$SHELL` (Linux). No UI to switch shells or set a default.
- **Apps tab icon** — `AppGalleryFiles` in `ToolboxOptions` does not reliably register apps in the MATLAB Apps toolstrip. The toolbox installs and works, but there is no icon in the Apps tab.
- **Session persistence** — Terminal sessions are not preserved across MATLAB restarts.
- **Multi-platform .mltbx** — Currently bundles the binary for one platform only. A single .mltbx supporting all platforms would require embedding all binaries and selecting at runtime.

### Known issues
- **Character swallowing** — The uihtml Data channel is property-based (last-write-wins). Fast typing can lose characters, especially in matlab-proxy. Future fix: migrate to `sendEventToMATLAB`/`sendEventToHTMLSource` (R2023a+).
- **Line wrapping in matlab-proxy** — Long lines may overwrite from the start instead of wrapping correctly.
- **uihtml caching** — MATLAB caches HTML/CSS files aggressively. Changes to the frontend require a MATLAB restart to take effect.

## License

Copyright 2026 The MathWorks, Inc.
