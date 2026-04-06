# Terminal in MATLAB 

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
- **Cross-platform** — Works on Linux, macOS, and Windows. Uses `creack/pty` on Unix and ConPTY on Windows.
- **Configurable shell** — Choose your shell via `Terminal(Shell="zsh")`. Defaults to `$SHELL` on Unix, `%COMSPEC%` on Windows.
- **Tabbed interface** — Open multiple terminal sessions in a single panel. Create, close, and switch tabs.
- **Docked in MATLAB Desktop** — The terminal panel docks into the MATLAB layout like any other tool window. Undock to a floating window with `WindowStyle="normal"`.
- **MATLAB theme integration** — Automatically inherits your MATLAB theme (light or dark), code font family, and font size. Theme is preserved when undocking or moving panels.
- **Copy and paste** — Ctrl+Shift+C to copy selection, Ctrl+Shift+V to paste.
- **Instance management** — `Terminal.list()` returns handles to all running terminals, `Terminal.closeAll()` closes them all.
- **Auto-cleanup** — Closing the last tab closes the window. The server process is killed when the terminal is deleted or MATLAB exits. Idle timeout as a safety net.
- **MATLAB environment variables** — Terminal sessions have `MATLAB_PID` and `MATLAB_ROOT` set, allowing CLI tools to discover the running MATLAB instance.
- **R2023a+ event API** — On MATLAB R2023a and later, uses the event-based `sendEventToHTMLSource`/`HTMLEventReceivedFcn` API for reliable keystroke delivery with no data loss. Older releases fall back to the Data channel with buffering.
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

% Open with a specific shell
t = Terminal(Shell="zsh");            % Linux/macOS
t = Terminal(Shell="powershell.exe"); % Windows

% Query the shell in use
t.Shell

% List all running terminals
Terminal.list()

% Close all running terminals
Terminal.closeAll()

% Close a single terminal
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
- Linux, macOS, or Windows

The exact minimum MATLAB release is yet to be determined. The following features constrain it:

| Feature | Minimum Release |
|---------|----------------|
| `uihtml` | R2019b |
| `arguments` blocks | R2019b |
| `uifigure` `WindowStyle='modal'` | R2020b |
| `uifigure` `WindowStyle='docked'` | TBD |
| `settings().matlab.editor.colortheme` | TBD |
| `isMATLABReleaseOlderThan` | R2020b |
| `sendEventToHTMLSource` / `HTMLEventReceivedFcn` (optional, improves typing) | R2023a |
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
│   ├── pty.go                      # Platform-agnostic PTY interface
│   ├── pty_unix.go                 # Unix PTY implementation (creack/pty)
│   ├── pty_windows.go              # Windows PTY implementation (ConPTY)
│   ├── shell_unix.go               # Default shell detection (Unix)
│   ├── shell_windows.go            # Default shell detection (Windows)
│   ├── auth.go                     # Token validation middleware
│   └── go.mod / go.sum             # Go dependencies
├── build/                          # Build tooling (not shipped in .mltbx)
│   ├── build_assets.m              # Bundles web assets + binary into .mat
│   ├── package.m                   # Builds .mltbx (calls build_assets.m)
│   └── setup_xterm.sh              # Downloads and vendors xterm.js
├── dist/                           # Build output (gitignored)
│   ├── glnxa64/                    # Linux binary
│   ├── maci64/                     # macOS Intel binary
│   ├── maca64/                     # macOS Apple Silicon binary
│   ├── win64/                      # Windows binary
│   └── Terminal.mltbx              # Installable toolbox package
├── DESIGN.md                       # Architecture decisions and security analysis
└── README.md
```

### Architecture

```
MATLAB (Terminal.m)  ←— Event API (R2023a+) / Data channel —→  uihtml (xterm.js)
        │
        │  HTTP polling (100ms)
        ▼
Go server (matlab-terminal-server)  ←→  PTY sessions (creack/pty on Unix, ConPTY on Windows)
```

- **Frontend**: xterm.js in MATLAB's `uihtml`. All JS is inline (uihtml sandboxes external scripts).
- **Backend**: Go binary managing PTY sessions over a localhost HTTP API with token auth.
- **Bridge**: MATLAB polls the server and relays output to JS. JS input is queued and sent through MATLAB.
- **Communication**: On R2023a+, uses the event-based API (`sendEventToHTMLSource`/`HTMLEventReceivedFcn`) for reliable message delivery. On older releases, falls back to the Data channel with buffering to mitigate last-write-wins behavior.

See [DESIGN.md](DESIGN.md) for detailed architecture decisions and security analysis.

### Development Setup

1. **Build the Go server** (requires Go 1.21+):
   ```bash
   cd server/
   ```
   Build into `dist/<arch>/` where `<arch>` matches your platform:

   | Platform | `<arch>` | Build command |
   |----------|----------|---------------|
   | Linux x86_64 | `glnxa64` | `mkdir -p ../dist/glnxa64 && go build -o ../dist/glnxa64/matlab-terminal-server .` |
   | macOS Intel | `maci64` | `mkdir -p ../dist/maci64 && GOARCH=amd64 go build -o ../dist/maci64/matlab-terminal-server .` |
   | macOS Apple Silicon | `maca64` | `mkdir -p ../dist/maca64 && GOARCH=arm64 go build -o ../dist/maca64/matlab-terminal-server .` |
   | Windows x86_64 | `win64` | `mkdir -p ../dist/win64 && GOOS=windows GOARCH=amd64 go build -o ../dist/win64/matlab-terminal-server.exe .` |

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

Requires MATLAB and compiled Go binaries in `dist/<arch>/`.

```matlab
cd /path/to/matlab-terminal

% This runs build_assets.m (packs HTML + binary into .mat) then packageToolbox.
run('build/package.m')
```

Output: `dist/Terminal.mltbx`

#### What `package.m` does

1. **`build_assets.m`** — Reads `html/` files and all server binaries from `dist/<arch>/`, packs them as byte arrays into `toolbox/web_assets.mat`. This works around `packageToolbox` silently dropping `.html`, `.css`, `.js`, and binary files.
2. **`packageToolbox`** — Creates the `.mltbx` from `toolbox/`, which now includes the `.mat` alongside the `.m` files.

At runtime, `Terminal.m` extracts assets from `web_assets.mat` to `prefdir/matlab-terminal/` on first launch (version-stamped to avoid re-extraction).

### CI/CD Pipeline (GitHub Actions)

A release build involves three stages: cross-compiling Go binaries for all platforms, bundling them into a `.mltbx`, and creating a GitHub Release.

The workflow is defined in `.github/workflows/release.yml` and triggered by pushing a version tag:

```bash
git tag v0.1.0
git push origin v0.1.0
```

**Pipeline stages:**

1. **`build-server`** — Cross-compiles the Go binary for Linux (`glnxa64`), macOS Intel (`maci64`), macOS Apple Silicon (`maca64`), and Windows (`win64`) in parallel using a build matrix.
2. **`build-mltbx`** — Downloads all binaries into `dist/<arch>/`, sets up MATLAB via `matlab-actions/setup-matlab`, and runs `build/package.m` to create a single `.mltbx` containing all platform binaries.
3. **`release`** — Creates a GitHub Release with the `.mltbx` attached and commit-based release notes.

> **Note**: The `matlab-actions/setup-matlab` action requires a [MATLAB license](https://github.com/matlab-actions/setup-matlab#use-matlab-batch-licensing-token). For public repositories, MathWorks provides free CI licenses via [MATLAB batch licensing tokens](https://www.mathworks.com/help/cloudcenter/ug/matlab-batch-licensing-tokens.html).

The resulting `.mltbx` is a single cross-platform artifact. At install time, `Terminal.m` extracts the correct binary for the user's platform based on `computer('arch')`.

## Known Limitations and Roadmap

### Not yet implemented
- **Apps tab icon** — `AppGalleryFiles` in `ToolboxOptions` does not reliably register apps in the MATLAB Apps toolstrip. The toolbox installs and works, but there is no icon in the Apps tab.
- **Session persistence** — Terminal sessions are not preserved across MATLAB restarts.

### Known issues
- **Character swallowing on pre-R2023a** — The legacy Data channel is property-based (last-write-wins). Fast typing can lose characters, especially in matlab-proxy. On R2023a+, the event-based API eliminates this issue.
- **Line wrapping in matlab-proxy** — Long lines may overwrite from the start instead of wrapping correctly.
- **uihtml caching** — MATLAB caches HTML/CSS files aggressively. Changes to the frontend require a MATLAB restart to take effect.

## License

Copyright 2026 The MathWorks, Inc.
