# Terminal in MATLAB®

[![Open in MATLAB Online](https://www.mathworks.com/images/responsive/global/open-in-matlab-online.svg)](https://matlab.mathworks.com/open/github/v1?repo=prabhakk-mw/matlab-terminal&file=toolbox/doc/Install.m) &nbsp; [![Download Latest](https://img.shields.io/github/v/release/prabhakk-mw/matlab-terminal?label=Download%20Latest&logo=github)](../../releases/latest/download/Terminal.mltbx)

Embed a full system terminal in the MATLAB® Desktop. Run shell commands, `git`, `docker`, AI coding agents, and other CLI tools without leaving MATLAB.

<video src="https://github.com/user-attachments/assets/da4858b9-684f-43ad-9e66-bb64ab268d03" autoplay loop muted playsinline></video>

## Installation

Download [`Terminal.mltbx`](../../releases/latest/download/Terminal.mltbx) and install:

```matlab
matlab.addons.install('Terminal.mltbx')
```

On first launch, bundled assets are automatically extracted to a local cache. No additional setup is required.

### Requirements

- MATLAB R2024b or later

## Getting Started

```matlab
% Open a docked terminal
t = terminal();

% Open with a custom title
t = terminal(Name="Build");

% Open in a floating window
t = terminal(WindowStyle="normal");

% Open with a specific shell
t = terminal(Shell="zsh");            % Linux/macOS
t = terminal(Shell="powershell.exe"); % Windows

% Open with a color theme
t = terminal(Theme="dracula");
t = terminal(Theme="solarized-light");

% Change theme on the fly
t.Theme = "monokai";

% List all running terminals
terminal.list()

% Close all running terminals
terminal.closeAll()

% Close a single terminal
delete(t);

% Query the shell in use
t.Shell

% Check the installed version
terminal.version()

% Set up AI agent integration with MathWorks toolkits
t = terminal(Agentic=true);

% Check for updates and install the latest version from GitHub
terminal.update()

% Run the built-in test suite
terminal.test()
```

| Shortcut     | Action                     |
| ------------ | -------------------------- |
| Ctrl+Shift+C | Copy selection             |
| Ctrl+Shift+V | Paste                      |
| `exit`       | Close current terminal tab |

## AI Agent Integration

Terminal can set up AI coding agents to work with MATLAB and Simulink via the [Model Context Protocol (MCP)](https://modelcontextprotocol.io). This allows agents like Claude, Codex, Copilot, Gemini, Cursor, and Amp to evaluate MATLAB code, run files, interact with the editor, and build Simulink models.

```matlab
t = terminal(Agentic=true);
```

On first run, a setup wizard prompts you to select an agent and toolkits. Preferences are saved for subsequent runs.

### Supported Agents

| Agent   | Registration                                  |
| ------- | --------------------------------------------- |
| Claude  | CLI command pre-populated in terminal         |
| Codex   | CLI command pre-populated in terminal         |
| Copilot | Config written to `.vscode/settings.json`     |
| Gemini  | Config written to `.gemini/settings.json`     |
| Cursor  | Config written to `.cursor/mcp.json`          |
| Amp     | Config written to `.config/amp/settings.json` |

### Toolkits

- **[MATLAB Agentic Toolkit](https://github.com/matlab/matlab-agentic-toolkit)** — MCP tools + skills for MATLAB (evaluate code, run files, run tests, check code, detect errors, and more)
- **[Simulink Agentic Toolkit](https://github.com/matlab/simulink-agentic-toolkit)** — MCP tools + skills for Simulink model building

Toolkits are downloaded automatically from GitHub on first use.

### Editor Tools

Terminal bundles additional MCP tools that give AI agents read-only access to the MATLAB editor:

| Tool                      | Description                                                |
| ------------------------- | ---------------------------------------------------------- |
| `matlab_editor_list`      | List all files open in the editor with modification status |
| `matlab_editor_active`    | Get the active file, cursor position, and selected text    |
| `matlab_editor_selection` | Get the currently highlighted text                         |
| `matlab_editor_read`      | Read contents of an open file (reflects unsaved edits)     |

### Skipping the Wizard

Pass `AgentOptions` to skip the interactive wizard:

```matlab
t = terminal(Agentic=true, AgentOptions=struct('Agent',"claude",'Toolkits',["matlab"]));
t = terminal(Agentic=true, AgentOptions=struct('Agent',"gemini",'Toolkits',["matlab","simulink"]));
```

Save preferences so future calls use the same options:

```matlab
terminal.setAgentOptions(struct('Agent',"claude",'Toolkits',["matlab"]));
t = terminal(Agentic=true);  % uses saved options
```

### Managing Toolkits

```matlab
terminal.updateAgenticToolkit()            % update all installed toolkits
terminal.updateAgenticToolkit("matlab")    % update MATLAB toolkit only
terminal.updateAgenticToolkit("simulink")  % update Simulink toolkit only
terminal.resetAgentOptions()               % clear preferences, re-run wizard
```

### Requirements

- [MATLAB MCP Core Server Toolkit](https://github.com/matlab/matlab-mcp-core-server) (auto-installed on first use)
- `matlab-mcp-core-server` binary v0.8.0 or later (auto-downloaded on first use)

### How It Works

`terminal(Agentic=true)` shares the MATLAB Embedded Connector so the MCP Core Server can connect to the running MATLAB session. It downloads the selected agentic toolkits, merges their tool definitions with the bundled editor tools, and registers the MCP server with your chosen AI agent. For CLI agents (Claude, Codex), the registration command is pre-populated in the terminal. For config-file agents (Copilot, Gemini, Cursor, Amp), the config is written directly.

## Updating

```matlab
terminal.update()
```

This queries GitHub for the latest release, displays a version comparison, and prompts for confirmation before upgrading. The update process closes all open terminals, uninstalls the current version, clears cached assets, downloads the new `.mltbx`, and installs it.

![terminal.update() output](images/update.png)

## Uninstalling

```matlab
matlab.addons.uninstall('Terminal')
```

## Features

- **Full terminal emulator** — PTY-based with 256-color support, cursor movement, and escape sequences. Interactive tools like `vim`, `htop`, and `ssh` work correctly.
- **Cross-platform** — Linux, macOS, and Windows. Uses `creack/pty` on Unix and ConPTY on Windows.
- **Configurable shell** — Specify a shell with `terminal(Shell="zsh")`. Defaults to `$SHELL` on Unix, `%COMSPEC%` on Windows.
- **Tabbed interface** — Open multiple terminal sessions in a single panel. Create, close, and switch tabs.

  ![Multiple tabs](images/tabs.png)

- **Docked in MATLAB Desktop** — The terminal panel docks into the MATLAB layout like any other tool window. Undock to a floating window with `WindowStyle="normal"`.
- **Theme integration** — Follows the MATLAB theme by default, or choose from built-in presets like Dracula, Monokai, Nord, and more. Change themes on the fly with `t.Theme = "dracula"`. See [Themes](#themes) for the full list and customization options.

  | Light                                  | Dark                                 |
  | -------------------------------------- | ------------------------------------ |
  | ![Light theme](images/theme-light.png) | ![Dark theme](images/theme-dark.png) |

- **Copy and paste** — Ctrl+Shift+C to copy, Ctrl+Shift+V to paste.
- **Instance management** — `terminal.list()` returns handles to all running terminals. `terminal.closeAll()` closes them all.
- **Self-updating** — `terminal.update()` checks GitHub for new releases and walks through the upgrade interactively.
- **Auto-cleanup** — Closing the last tab closes the window. The server process is terminated when the terminal is deleted or MATLAB exits. An idle timeout acts as a safety net.
- **Environment variables** — Terminal sessions have `MATLAB_PID` and `MATLAB_ROOT` set, allowing CLI tools to discover the running MATLAB instance.
- **AI agent integration** — `terminal(Agentic=true)` sets up AI coding agents (Claude, Codex, Copilot, Gemini, Cursor, Amp) to work with MATLAB and Simulink via MCP. See [AI Agent Integration](#ai-agent-integration) for details.
- **Event API (R2023a+)** — On R2023a and later, uses `sendEventToHTMLSource`/`HTMLEventReceivedFcn` for reliable keystroke delivery with no data loss. Older releases fall back to the Data channel with buffering.
- **matlab-proxy compatible** — Works in browser-based MATLAB via [matlab-proxy](https://github.com/mathworks/matlab-proxy).
- **Zero runtime dependencies** — No Node.js®, Python®, or Java® required. A single Go binary handles all PTY management.

### Release-Dependent Behavior

| Behavior                    | Details                                                                                                                                                                                       |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Docked window style         | Supported on releases where `uifigure` accepts `WindowStyle='docked'`. On releases that do not support it (e.g., R2024a), the terminal falls back to a normal floating window with a warning. |
| Reliable keystroke delivery | R2023a and later use the event-based API with no data loss. Older releases use the Data channel with buffering; fast typing may lose characters.                                              |
| Live theme switching        | Detects MATLAB theme changes by polling `DefaultFigureColor`. On releases where this property does not update, restart the terminal to pick up theme changes.                                 |

## Known Limitations

- **Session persistence** — Terminal sessions are not preserved across MATLAB restarts.
- **Docked mode not available on all releases** — `uifigure` `WindowStyle='docked'` is not supported on some releases (e.g., R2024a). The terminal automatically falls back to a normal floating window.
- **Character swallowing on pre-R2023a** — The legacy Data channel is property-based (last-write-wins). Fast typing can lose characters, especially in matlab-proxy. On R2023a and later, the event-based API eliminates this issue.
- **Line wrapping in matlab-proxy** — Long lines may overwrite from the start instead of wrapping correctly.
- **Terminal unresponsive during computation** — The terminal relies on the MATLAB main thread for polling the server and updating the UI. When MATLAB is busy executing code, the terminal freezes until MATLAB returns to idle. This is a fundamental constraint of `uihtml`, which cannot load URLs — JS cannot communicate directly with the server via WebSocket, so all I/O must be routed through MATLAB.
- **uihtml caching** — MATLAB caches HTML and CSS files aggressively. Changes to the frontend require a MATLAB restart to take effect.

## Themes

By default, Terminal follows the MATLAB Desktop theme — light or dark — and updates automatically when the MATLAB theme changes. Override this with a named preset, or define a fully custom color scheme.

### Using a Preset Theme

```matlab
t = terminal(Theme="dracula");
```

Change the theme on an existing terminal:

```matlab
t.Theme = "nord";
```

### Available Presets

| Preset               | Description                                |
| -------------------- | ------------------------------------------ |
| `"auto"`             | Follows the MATLAB Desktop theme (default) |
| `"light"`            | Light theme (white background)             |
| `"dark"`             | Dark theme (VS Code–style)                 |
| `"dracula"`          | Dracula                                    |
| `"monokai"`          | Monokai                                    |
| `"solarized-dark"`   | Solarized Dark                             |
| `"solarized-light"`  | Solarized Light                            |
| `"nord"`             | Nord                                       |
| `"gruvbox-dark"`     | Gruvbox Dark                               |
| `"one-dark"`         | Atom One Dark                              |
| `"tokyo-night"`      | Tokyo Night                                |
| `"catppuccin-mocha"` | Catppuccin Mocha                           |

List all available presets programmatically:

```matlab
terminal.themes()
```

### Custom Themes

Pass a struct with color fields to define a custom theme. Only include the fields you want to customize — any field you omit inherits its value from the built-in `"dark"` preset.

```matlab
% Only override background and foreground; all other colors come from "dark"
myTheme = struct( ...
    'background',  '#1a1a2e', ...
    'foreground',  '#e0e0e0');
t = terminal(Theme=myTheme);
```

A more complete example with cursor and selection colors:

```matlab
myTheme = struct( ...
    'background',  '#1a1a2e', ...
    'foreground',  '#e0e0e0', ...
    'cursor',      '#ff6b6b', ...
    'selectionBackground', '#3a3a5e');
t = terminal(Theme=myTheme);
```

For full control over the ANSI color palette, include any of the 16 standard color fields. These control how programs like `ls`, `git`, and shell prompts render colored output:

```matlab
myTheme = struct( ...
    'background',  '#1a1a2e', ...
    'foreground',  '#e0e0e0', ...
    'cursor',      '#ff6b6b', ...
    'selectionBackground', '#3a3a5e', ...
    'black',       '#1a1a2e', ...
    'red',         '#ff6b6b', ...
    'green',       '#a8cc8c', ...
    'yellow',      '#dbab79', ...
    'blue',        '#71bef2', ...
    'magenta',     '#d290e4', ...
    'cyan',        '#66c2cd', ...
    'white',       '#e0e0e0', ...
    'brightBlack', '#545862', ...
    'brightRed',   '#ff8a8a', ...
    'brightGreen', '#b5d4a0', ...
    'brightYellow','#e8c48d', ...
    'brightBlue',  '#84cbf5', ...
    'brightMagenta','#dca4ea', ...
    'brightCyan',  '#79d2da', ...
    'brightWhite', '#f0f0f0');
t = terminal(Theme=myTheme);
```

#### Supported Fields

All fields are optional. Values must be `'#rrggbb'` hex color strings.

| Field                 | Description                                | Default (from `"dark"` preset) |
| --------------------- | ------------------------------------------ | ------------------------------ |
| `background`          | Terminal background                        | `'#1e1e1e'`                    |
| `foreground`          | Default text color                         | `'#d4d4d4'`                    |
| `cursor`              | Cursor color                               | `'#aeafad'`                    |
| `cursorAccent`        | Cursor text color (character under cursor) | Same as `background`           |
| `selectionBackground` | Selected text highlight                    | `'#264f78'`                    |
| `black`               | ANSI black (color 0)                       | xterm.js default               |
| `red`                 | ANSI red (color 1)                         | xterm.js default               |
| `green`               | ANSI green (color 2)                       | xterm.js default               |
| `yellow`              | ANSI yellow (color 3)                      | xterm.js default               |
| `blue`                | ANSI blue (color 4)                        | xterm.js default               |
| `magenta`             | ANSI magenta (color 5)                     | xterm.js default               |
| `cyan`                | ANSI cyan (color 6)                        | xterm.js default               |
| `white`               | ANSI white (color 7)                       | xterm.js default               |
| `brightBlack`         | ANSI bright black (color 8)                | xterm.js default               |
| `brightRed`           | ANSI bright red (color 9)                  | xterm.js default               |
| `brightGreen`         | ANSI bright green (color 10)               | xterm.js default               |
| `brightYellow`        | ANSI bright yellow (color 11)              | xterm.js default               |
| `brightBlue`          | ANSI bright blue (color 12)                | xterm.js default               |
| `brightMagenta`       | ANSI bright magenta (color 13)             | xterm.js default               |
| `brightCyan`          | ANSI bright cyan (color 14)                | xterm.js default               |
| `brightWhite`         | ANSI bright white (color 15)               | xterm.js default               |

#### Validation

Custom theme structs are validated when set. Terminal raises an error for:

- **Unknown field names** — catches typos like `'backgroud'` instead of `'background'`
- **Invalid color format** — values must be `'#rrggbb'` hex strings (e.g., `'#ff0000'`, not `'red'` or `'#f00'`)

```matlab
% Typo in field name → error
terminal(Theme=struct('backgroud', '#1e1e1e'))
% Error: Unknown theme field "backgroud". Valid fields: background, foreground, ...

% Invalid color format → error
terminal(Theme=struct('background', 'red'))
% Error: Theme field "background" has invalid value "red". Use '#rrggbb' hex format.
```

### Default Theme

Set a default theme that applies to all new terminals and persists across MATLAB sessions:

```matlab
terminal.setDefaultTheme("dracula")
```

New terminals use this theme unless overridden with the `Theme` argument:

```matlab
t1 = terminal();                  % uses "dracula"
t2 = terminal(Theme="nord");      % overrides to "nord"
```

Query and reset the default:

```matlab
terminal.getDefaultTheme()        % returns "dracula"
terminal.setDefaultTheme("auto")  % reset to follow MATLAB theme
```

## Developer Guide

### Repository Structure

```
matlab-terminal/
├── toolbox/                        # Toolbox source (becomes .mltbx content)
│   ├── terminal.m                  # Main MATLAB class
│   ├── terminalVersion.m          # Version string (stamped at build time)
│   ├── openTerminal.m              # Launcher for Apps tab
│   ├── +internal/                  # Internal package (not user-facing)
│   │   └── Themes.m               # Theme presets, validation, and resolution
│   ├── +terminaltools/          # MCP extension tools for AI agent access
│   │   ├── matlab-editor-tools.json  # Tool definitions for --extension-file
│   │   ├── matlab_editor_list.m
│   │   ├── matlab_editor_active.m
│   │   ├── matlab_editor_read.m
│   │   └── matlab_editor_selection.m
│   ├── tests/                      # MATLAB test suite (bundled in .mltbx)
│   │   ├── TestTerminalUnit.m     # Unit tests (no display or server required)
│   │   └── TestTerminalIntegration.m # Integration tests (require display + binary)
│   ├── doc/                        # Documentation
│   │   └── GettingStarted.m       # Getting Started guide (shown on install)
│   ├── images/                     # Toolbox icon
│   │   └── matlab-terminal.jpeg
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
│   ├── auth_test.go                # Auth unit tests
│   ├── api_test.go                 # API handler unit tests
│   ├── integration_test.go         # HTTP integration tests
│   └── go.mod / go.sum             # Go dependencies
├── build/                          # Build tooling (not shipped in .mltbx)
│   ├── build_assets.m              # Bundles web assets + binary into .mat
│   ├── package.m                   # Builds .mltbx (function, accepts version arg)
│   └── setup_xterm.sh              # Downloads and vendors xterm.js
├── dist/                           # Build output (gitignored)
│   ├── glnxa64/                    # Linux binary
│   ├── maci64/                     # macOS Intel binary
│   ├── maca64/                     # macOS Apple Silicon binary
│   ├── win64/                      # Windows binary
│   └── Terminal.mltbx              # Installable toolbox package
├── DESIGN.md                       # Architecture decisions and security analysis
├── SECURITY.md                     # Vulnerability reporting and security details
└── README.md
```

### Architecture

```
MATLAB (terminal.m)  ←— Event API (R2023a+) / Data channel —→  uihtml (xterm.js)
        │
        │  HTTP polling (100ms)
        ▼
Go server (matlab-terminal-server)  ←→  PTY sessions (creack/pty on Unix, ConPTY on Windows)
```

- **Frontend**: xterm.js hosted in `uihtml`. All JS is inline (uihtml sandboxes external scripts).
- **Backend**: Go binary managing PTY sessions over a localhost HTTP API with token authentication.
- **Bridge**: MATLAB polls the server and relays output to JS. JS input is queued and sent through MATLAB.
- **Communication**: On R2023a and later, uses the event-based API (`sendEventToHTMLSource`/`HTMLEventReceivedFcn`) for reliable message delivery. On older releases, falls back to the Data channel with buffering to mitigate last-write-wins behavior.

See [DESIGN.md](DESIGN.md) for detailed architecture decisions and security analysis.

### Development Setup

1. **Build the Go server** (requires Go 1.21+):

   ```bash
   cd server/
   ```

   Build into `dist/<arch>/` where `<arch>` matches the platform:

   | Platform            | `<arch>`  | Build command                                                                                                |
   | ------------------- | --------- | ------------------------------------------------------------------------------------------------------------ |
   | Linux x86_64        | `glnxa64` | `mkdir -p ../dist/glnxa64 && go build -o ../dist/glnxa64/matlab-terminal-server .`                           |
   | macOS Intel         | `maci64`  | `mkdir -p ../dist/maci64 && GOARCH=amd64 go build -o ../dist/maci64/matlab-terminal-server .`                |
   | macOS Apple Silicon | `maca64`  | `mkdir -p ../dist/maca64 && GOARCH=arm64 go build -o ../dist/maca64/matlab-terminal-server .`                |
   | Windows x86_64      | `win64`   | `mkdir -p ../dist/win64 && GOOS=windows GOARCH=amd64 go build -o ../dist/win64/matlab-terminal-server.exe .` |

2. **Add the toolbox to the MATLAB path**:

   ```matlab
   addpath('/path/to/matlab-terminal/toolbox')
   ```

3. **Launch**:
   ```matlab
   terminal()
   ```

When running from source, `terminal.m` uses `html/` directly and finds the server binary in `dist/<arch>/`. No `.mat` extraction is needed.

### Testing

Terminal ships with a comprehensive test suite that covers both the Go server and the MATLAB toolbox. Tests are bundled inside the `.mltbx`, so end users can verify their installation without cloning the repository or installing a Go compiler.

#### Running Tests from an Installed Toolbox

After installing `Terminal.mltbx`, run the full test suite from the MATLAB Command Window:

```matlab
terminal.test()
```

This discovers and runs all test classes, prints a verbose summary to the command window, and generates an HTML report in a `test-results/` folder in the current directory:

```
Terminal Test Suite v0.9.2

Found 62 tests in /path/to/toolbox/tests

Running TestTerminalUnit
  ...
Running TestTerminalIntegration
  ...

Results: 40/62 passed, 22 skipped
Report: test-results/index.html
```

To capture the results programmatically:

```matlab
results = terminal.test();
disp(table(results))
```

#### Test Tiers

| Test class                | What it covers                                                                                                                                                                                                       | Requirements                               |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| `TestTerminalUnit`        | Static APIs (`version`, `generateToken`, `themes`, `setDefaultTheme`/`getDefaultTheme`, `list`, `closeAll`), theme validation, theme resolution, token cryptographic strength                                        | MATLAB only — no display, no server binary |
| `TestTerminalIntegration` | Constructor with all Name-Value pairs (`Name`, `WindowStyle`, `Shell`, `Theme`), parent embedding (`uifigure`, `uipanel`), lifecycle (`delete`, `list`, `closeAll`), live theme switching, default theme inheritance | Display (uifigure) + server binary         |

Integration tests skip automatically with a diagnostic message when prerequisites are not met (e.g., headless environment or missing binary). Unit tests always run.

#### Running Tests from a Source Checkout

For developers working from a git clone:

1. Build the Go server for the current platform (see [Development Setup](#development-setup)).
2. Add the toolbox to the path:
   ```matlab
   addpath('toolbox')
   ```
3. Run the test suite:

   ```matlab
   terminal.test()
   ```

   Or run individual test classes:

   ```matlab
   runtests('toolbox/tests/TestTerminalUnit.m')
   runtests('toolbox/tests/TestTerminalIntegration.m')
   ```

#### Go Server Tests

The Go server has its own test suite that runs in CI on both Linux and Windows:

```bash
cd server/
go test -v -count=1 ./...
```

| Test file             | What it covers                                                                                                                                                                             |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `auth_test.go`        | Token validation (exact match, wrong token, empty, case sensitivity, substrings)                                                                                                           |
| `api_test.go`         | All HTTP handlers — auth rejection on every endpoint, wrong HTTP method, invalid JSON, oversized request body, poll message filtering, session listing, scrollback, last-activity tracking |
| `integration_test.go` | Full session lifecycle over HTTP — create, input, poll, resize, scrollback, close, shell exit detection, multi-session isolation                                                           |

### Building a Release

The release artifact is a single file: `Terminal.mltbx`. It bundles the MATLAB code, web frontend, and platform-specific Go binaries into a self-contained installable package.

#### Local build

Requires MATLAB and compiled Go binaries in `dist/<arch>/`.

```matlab
cd /path/to/matlab-terminal
addpath('build')

% Dev build (uses version from TerminalVersion.m, defaults to 0.0.0-dev)
package()

% Release build with explicit version
package("1.2.0")
```

Output: `dist/Terminal.mltbx`

#### What `package()` does

1. **Resolves version** — Uses the provided argument, or falls back to the value in `TerminalVersion.m`. Stamps `TerminalVersion.m` with the build version so it is baked into the `.mltbx`.
2. **Bundles assets** — `build_assets.m` reads `html/` files and all server binaries from `dist/<arch>/`, packing them as byte arrays into `toolbox/web_assets.mat`. This works around `packageToolbox` silently dropping `.html`, `.css`, `.js`, and binary files.
3. **Packages toolbox** — `packageToolbox` creates the `.mltbx` from `toolbox/`, which includes the `.mat` alongside `.m` files, the Getting Started guide, and the toolbox icon.

At runtime, `terminal.m` extracts assets from `web_assets.mat` into the toolbox directory (`html/` and `bin/matlab-terminal-server/<arch>/`) on first launch (version-stamped to avoid re-extraction). Only the binary for the current platform is extracted.

### CI/CD Pipeline (GitHub Actions)

A release build involves three stages: cross-compiling Go binaries for all platforms, bundling them into a `.mltbx`, and creating a GitHub Release.

The workflow is defined in `.github/workflows/release.yml` and triggered by pushing a version tag:

```bash
git tag v0.7.0
git push origin v0.7.0
```

**Pipeline stages:**

1. **`build-server`** — Cross-compiles the Go binary for Linux (`glnxa64`), macOS Intel (`maci64`), macOS Apple Silicon (`maca64`), and Windows (`win64`) in parallel using a build matrix.
2. **`build-mltbx`** — Downloads all binaries into `dist/<arch>/`, sets up MATLAB via `matlab-actions/setup-matlab`, and runs `package()` with the git tag as the version argument to create a single `.mltbx` containing all platform binaries.
3. **`release`** — Creates a GitHub Release with the `.mltbx` attached and commit-based release notes.

> **Note**: The `matlab-actions/setup-matlab` action requires a [MATLAB batch licensing token](https://www.mathworks.com/help/cloudcenter/ug/matlab-batch-licensing-tokens.html). MathWorks® provides free CI licenses for public repositories.

The resulting `.mltbx` is a single cross-platform artifact. At install time, `terminal.m` extracts the correct binary for the user's platform based on `computer('arch')`.

## License

See [LICENSE.md](LICENSE.md) for details.

## Community Support

This repository is maintained by The MathWorks, Inc. Filed issues are reviewed by maintainers but responses are not guaranteed.

- **Bug reports and feature requests** — [GitHub Issues](../../issues)
- **Security vulnerabilities** — Report to [security@mathworks.com](mailto:security@mathworks.com). See [SECURITY.md](SECURITY.md) for details.

---

Copyright 2026 The MathWorks, Inc.
