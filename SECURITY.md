# Security

## Reporting Security Vulnerabilities

If you believe you have discovered a security vulnerability, please report it to
security@mathworks.com instead of GitHub. Please see
[MathWorks Vulnerability Disclosure Policy for Security Researchers](https://www.mathworks.com/company/aboutus/policies_statements/vulnerability-disclosure-policy.html)
for additional information.

----

## Security Model

MATLAB Terminal launches a local Go server that manages PTY (pseudo-terminal) sessions. The terminal runs with the same permissions as the MATLAB process — there is no privilege escalation. This is the same trust model as VS Code's integrated terminal.

### Authentication

All HTTP communication between MATLAB and the Go server is protected by a per-session authentication token:

- MATLAB generates a random 32-character hex token at startup
- The token is passed to the Go server as a `--token` CLI argument
- Every HTTP request includes the token in the `Authorization` header
- The server rejects requests without a valid token using constant-time comparison

### Network Binding

The Go server binds exclusively to `127.0.0.1` (loopback) on a randomly assigned port. It is not accessible from the network.

### Process Lifecycle

- The server is started by MATLAB and killed when the terminal is closed or MATLAB exits
- An idle timeout (default 30 seconds) causes the server to self-terminate when no sessions are active
- The server monitors its parent PID and exits if the parent process dies

### Binary Integrity

When installed via `.mltbx`, the server binary is embedded in a `.mat` file and extracted locally on first run. For manual installation via `Terminal.install()`, SHA-256 checksums in `checksums.json` are verified after download.

---

Copyright 2026 The MathWorks, Inc.
