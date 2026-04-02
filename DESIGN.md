<!-- Copyright 2026 The MathWorks, Inc. -->

# Terminal in MATLAB — Design Document

## 1. Goals

### Primary Goal
Embed a fully functional terminal emulator into the MATLAB Desktop, enabling users to run CLI tools, AI coding agents (e.g., Claude Code), and system commands without leaving MATLAB.

### Secondary Goals
- Provide a native, polished experience that feels built into MATLAB
- Support AI-assisted development workflows (Claude Code, GitHub Copilot CLI, etc.)
- Bridge the gap between MATLAB and modern software development tooling
- Enable workflows that are currently impossible or awkward in MATLAB: git, Docker, pip/conda/npm, SSH, HPC job submission, CI/CD interaction

## 2. Requirements

### Functional Requirements

| ID | Requirement | Priority | Status |
|----|-------------|----------|--------|
| F1 | Full interactive terminal emulator (PTY-based) with support for colors, cursor movement, and escape sequences | Must | Done |
| F2 | Multiple terminal sessions via a tabbed interface within a single panel | Must | Done |
| F3 | Create, close, and switch between terminal tabs | Must | Done |
| F4 | Terminal panel can be docked into the MATLAB desktop layout | Must | Done |
| F5 | Terminal inherits MATLAB theme (light/dark), code font, and font size from MATLAB settings | Must | Done |
| F6 | Works on Windows, macOS, and Linux | Must | Linux only |
| F7 | Supports interactive CLI tools (Claude Code, vim, htop, ssh, etc.) | Must | Done |
| F8 | Terminal resizes correctly when the panel is resized | Must | Done |
| F9 | Copy/paste support with Ctrl+Shift+C / Ctrl+Shift+V | Should | Done |
| F10 | Configurable default shell (e.g., bash, zsh, PowerShell, cmd) | Should | Not started |
| F11 | Terminal remembers tab state within a MATLAB session | Should | Not started |

### Non-Functional Requirements

| ID | Requirement | Priority | Status |
|----|-------------|----------|--------|
| NF1 | No external runtime dependencies (no Node.js, Python, or Java required at runtime) | Must | Done |
| NF2 | Single self-contained binary for the terminal server, per platform | Must | Done |
| NF3 | Installation via MATLAB Add-On Explorer / File Exchange | Must | Partial |
| NF4 | First-run automatic extraction of bundled server binary | Must | Done |
| NF5 | App appears in the MATLAB Apps gallery toolbar | Must | Not working |
| NF6 | Server startup time under 1 second | Should | Done |
| NF7 | Low resource footprint (memory and CPU) when idle | Should | Done |
| NF8 | Graceful cleanup — no orphan processes when MATLAB exits | Must | Done |

## 3. Architecture

### Overview

```
┌─────────────────────────────────────────┐
│ MATLAB                                  │
│                                         │
│  Terminal.m ──── uihtml ──── xterm.js   │
│      │              ▲                   │
│      │              │ Data channel      │
│      │              ▼                   │
│      │     Poll timer (100ms)           │
│      │         │                        │
│      ▼         ▼                        │
│  HTTP polling + POST                    │
│      │                                  │
└──────┼──────────────────────────────────┘
       │ localhost:random-port
       ▼
┌──────────────────────┐
│ matlab-terminal-     │
│ server (Go binary)   │
│                      │
│  HTTP API + PTY      │
│  sessions            │
└──────────────────────┘
```

### Decision 1: xterm.js + uihtml for the frontend
**Choice**: Use MATLAB's `uihtml` component to host an xterm.js-based terminal UI.

**Rationale**:
- `uihtml` is the officially supported way to embed web content in MATLAB UI
- xterm.js is the industry-standard terminal emulator for the web (used by VS Code, Jupyter, Theia)
- Enables rich terminal rendering (256-color, Unicode) without building a custom renderer
- Tabbed interface is straightforward to build in HTML/CSS/JS

**Key constraint**: All JS must be inline in the HTML file. External `<script src>` files loaded in uihtml are sandboxed and cannot define `window.setup`.

### Decision 2: Go binary for the backend server
**Choice**: A single Go binary (`matlab-terminal-server`) manages PTY sessions and exposes them over HTTP.

**Rationale**:
- Go compiles to a single static binary per platform — no runtime dependencies
- Excellent cross-platform PTY support via `creack/pty`
- Low memory footprint and fast startup
- Easy to cross-compile for all target platforms

### Decision 3: HTTP polling (not WebSocket)
**Choice**: MATLAB polls the Go server via HTTP at 100ms intervals. JS communicates with MATLAB via the `uihtml` Data channel.

**Rationale**:
- uihtml serves pages over HTTPS, blocking `ws://` connections (mixed content policy)
- `wss://` with the server's self-signed cert also fails
- HTTP polling via MATLAB's `webread`/`webwrite` avoids these issues entirely
- The Data channel between JS and MATLAB is property-based (last-write-wins), so a JS-side message queue with 50ms spacing prevents message loss

**Critical constraint**: MATLAB cannot handle concurrent `webread`/`webwrite` calls. Events (timer callbacks, DataChangedFcn) are processed during web calls, causing re-entrant requests. All HTTP calls are serialized through a single poll timer with an outbound message queue.

### Decision 4: MATLAB manages the server lifecycle
**Choice**: The MATLAB `Terminal` class starts the Go binary on construction and kills it on cleanup/deletion.

**Rationale**:
- MATLAB "owns" the process — no orphans
- `delete` method ensures the server stops when the terminal panel closes
- The Go binary also self-terminates after an idle timeout as a safety net

### Decision 5: Asset bundling via .mat file
**Choice**: Web assets (HTML, CSS, JS) and the server binary are bundled in a `web_assets.mat` file within the .mltbx toolbox. They are extracted to `prefdir/matlab-terminal/` on first run.

**Rationale**:
- `packageToolbox` silently drops `.html`, `.css`, `.js`, and binary executable files
- `.mat` files are included by the packager without issues
- Version-stamped extraction avoids redundant work on subsequent launches
- Development use (running from source) bypasses extraction and uses files directly

## 4. Security

### 4.1 Server Authentication
The Go server requires a per-session authentication token (32-char hex string) passed via the `Authorization` HTTP header. MATLAB generates this token at startup and passes it to the server as a CLI argument. The token is never exposed in HTML source.

### 4.2 Network Binding
The server binds exclusively to `127.0.0.1` (not `0.0.0.0`) on a randomly assigned port — no network exposure.

### 4.3 Command Execution
The terminal inherently provides shell access. This is by design, with the same trust model as VS Code's integrated terminal. The terminal runs with the same permissions as the MATLAB process.

### 4.4 Binary Integrity
The server binary is bundled in `web_assets.mat` and extracted locally. For manual installation via `Terminal.install()`, SHA-256 checksums in `checksums.json` are verified after download.

### 4.5 Orphan Processes
- Go binary implements an idle timeout — self-terminates when no sessions are active
- MATLAB's `delete` method sends `kill` to the server process
- The server monitors MATLAB's PID and can exit if the parent dies

## 5. Project Structure

```
matlab-terminal/
├── toolbox/                        # MATLAB Toolbox (.mltbx source)
│   ├── Terminal.m                  # Main MATLAB class
│   ├── openTerminal.m              # Simple launcher for Apps tab
│   ├── installServer.m             # Convenience wrapper for Terminal.install()
│   ├── checksums.json              # SHA-256 hashes for download verification
│   ├── web_assets.mat              # Bundled HTML/CSS/JS + binary (generated)
│   └── html/                       # Web assets (used in dev, bundled for release)
│       ├── index.html              # Host page with ALL JS inline (uihtml requirement)
│       ├── terminal.css            # Tab bar + theme + loading overlay styles
│       └── lib/xterm/              # Vendored xterm.js + fit addon
├── server/                         # Go server source
│   ├── main.go                     # Entry point, CLI flags, HTTP routes
│   ├── api.go                      # HTTP API handlers
│   ├── session.go                  # PTY session lifecycle
│   ├── auth.go                     # Token validation middleware
│   └── go.mod / go.sum             # Go module dependencies
├── build/                          # Build tooling (not shipped in .mltbx)
│   ├── build_assets.m              # Packs web assets + binary into .mat
│   ├── package.m                   # Builds .mltbx (calls build_assets.m)
│   └── setup_xterm.sh              # Downloads and vendors xterm.js
├── dist/                           # Build output (gitignored)
│   ├── matlab-terminal-server      # Compiled Go binary
│   └── Terminal.mltbx              # Installable toolbox package
└── DESIGN.md                       # This document
```

## 6. HTTP API Protocol

All communication between MATLAB and the Go server uses JSON over HTTP.

### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/create` | Create a new PTY session (`cols`, `rows`) → `{id}` |
| POST | `/api/input` | Send keystrokes to a session (`id`, `data`) |
| POST | `/api/resize` | Resize a session's PTY (`id`, `cols`, `rows`) |
| POST | `/api/close` | Close a session (`id`) |
| GET | `/api/poll?since=N` | Long-poll for output since sequence N → `{messages}` |
| GET | `/api/sessions` | Get active session count → `{count}` |

### Message Types (in poll response)

| Type | Fields | Description |
|------|--------|-------------|
| `output` | `id`, `seq`, `data` (base64) | Terminal output from a session |
| `exited` | `id`, `seq`, `exitCode` | Session's shell process exited |

## 7. Data Flow

```
User types → xterm.js onData → JS input buffer (80ms)
  → Data channel → MATLAB onJSMessage → OutQueue
  → Poll timer drains queue → POST /api/input → Go server → PTY

PTY output → Go server buffers → GET /api/poll (100ms)
  → MATLAB pollOutput → Data channel → JS handleMATLABMessage
  → xterm.js terminal.write()
```

## 8. Known Limitations

- **Character swallowing**: The Data channel is property-based (last-write-wins). Fast typing can lose characters, especially in matlab-proxy. Mitigation: JS-side input buffering (80ms) and message queue (50ms spacing). Future fix: migrate to `sendEventToMATLAB`/`sendEventToHTMLSource` (R2023a+).
- **Line wrapping in matlab-proxy**: Long lines may overwrite from the start instead of wrapping correctly.
- **Apps tab icon**: `AppGalleryFiles` in `ToolboxOptions` does not reliably register apps in the MATLAB Apps toolstrip.
- **Platform support**: Currently Linux only. macOS and Windows support requires cross-compilation and testing.
- **uihtml caching**: MATLAB caches HTML/CSS files aggressively. Changes require a MATLAB restart to take effect.
