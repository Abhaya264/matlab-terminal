// Copyright 2026 The MathWorks, Inc.

package main

import (
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"strings"
	"sync"
	"syscall"

	"github.com/creack/pty"
)

// Session represents a single PTY session.
type Session struct {
	ID   string
	cmd  *exec.Cmd
	ptmx *os.File

	mu     sync.Mutex
	closed bool
}

// OutputCallback is called when there is output from a session.
type OutputCallback func(sessionID string, data []byte)

// ExitCallback is called when a session's process exits.
type ExitCallback func(sessionID string, exitCode int)

// SessionManager manages multiple PTY sessions.
type SessionManager struct {
	mu       sync.Mutex
	sessions map[string]*Session

	defaultShell string
	extraEnv     []string

	nextID int
}

// NewSessionManager creates a new session manager.
func NewSessionManager(defaultShell string, extraEnv []string) *SessionManager {
	return &SessionManager{
		sessions:     make(map[string]*Session),
		defaultShell: defaultShell,
		extraEnv:     extraEnv,
	}
}

// Create starts a new PTY session. It calls onOutput for stdout data and
// onExit when the process terminates.
func (m *SessionManager) Create(shell string, cols, rows uint16, onOutput OutputCallback, onExit ExitCallback) (string, error) {
	if shell == "" {
		shell = m.defaultShell
	}

	m.mu.Lock()
	m.nextID++
	id := fmt.Sprintf("s%d", m.nextID)
	m.mu.Unlock()

	cmd := exec.Command(shell)
	// Build env: start with OS env, filter out TERM (MATLAB sets TERM=dumb),
	// then add our extras and force xterm-256color.
	env := os.Environ()
	filtered := make([]string, 0, len(env))
	for _, e := range env {
		if !strings.HasPrefix(e, "TERM=") {
			filtered = append(filtered, e)
		}
	}
	cmd.Env = append(filtered, m.extraEnv...)
	cmd.Env = append(cmd.Env, "TERM=xterm-256color")

	// Start with PTY.
	ptmx, err := pty.StartWithSize(cmd, &pty.Winsize{
		Cols: cols,
		Rows: rows,
	})
	if err != nil {
		return "", fmt.Errorf("failed to start pty: %w", err)
	}

	sess := &Session{
		ID:   id,
		cmd:  cmd,
		ptmx: ptmx,
	}

	m.mu.Lock()
	m.sessions[id] = sess
	m.mu.Unlock()

	// Read goroutine: reads PTY output and sends to callback.
	go func() {
		buf := make([]byte, 4096)
		for {
			n, err := ptmx.Read(buf)
			if n > 0 {
				data := make([]byte, n)
				copy(data, buf[:n])
				onOutput(id, data)
			}
			if err != nil {
				if err != io.EOF {
					log.Printf("session %s read error: %v", id, err)
				}
				break
			}
		}

		// Wait for process to exit and get exit code.
		exitCode := 0
		if err := cmd.Wait(); err != nil {
			if exitErr, ok := err.(*exec.ExitError); ok {
				if status, ok := exitErr.Sys().(syscall.WaitStatus); ok {
					exitCode = status.ExitStatus()
				}
			}
		}

		m.mu.Lock()
		delete(m.sessions, id)
		m.mu.Unlock()

		onExit(id, exitCode)
	}()

	return id, nil
}

// Write sends input data to a session's PTY.
func (m *SessionManager) Write(id string, data []byte) error {
	sess := m.get(id)
	if sess == nil {
		return fmt.Errorf("session %s not found", id)
	}
	_, err := sess.ptmx.Write(data)
	return err
}

// Resize changes the PTY window size.
func (m *SessionManager) Resize(id string, cols, rows uint16) error {
	sess := m.get(id)
	if sess == nil {
		return fmt.Errorf("session %s not found", id)
	}
	return pty.Setsize(sess.ptmx, &pty.Winsize{
		Cols: cols,
		Rows: rows,
	})
}

// Close terminates a session.
func (m *SessionManager) Close(id string) error {
	sess := m.get(id)
	if sess == nil {
		return fmt.Errorf("session %s not found", id)
	}

	sess.mu.Lock()
	defer sess.mu.Unlock()

	if sess.closed {
		return nil
	}
	sess.closed = true

	// Close PTY (this will cause the read goroutine to exit).
	sess.ptmx.Close()

	// Signal the process to terminate.
	if sess.cmd.Process != nil {
		sess.cmd.Process.Signal(syscall.SIGTERM)
	}

	return nil
}

// Count returns the number of active sessions.
func (m *SessionManager) Count() int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return len(m.sessions)
}

func (m *SessionManager) get(id string) *Session {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.sessions[id]
}
