// Copyright 2026 The MathWorks, Inc.

package main

import (
	"fmt"
	"io"
	"log"
	"sync"
)

// Session represents a single PTY session.
type Session struct {
	ID  string
	pty ptyProcess

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

	nextID int
}

// NewSessionManager creates a new session manager.
func NewSessionManager(defaultShell string) *SessionManager {
	return &SessionManager{
		sessions:     make(map[string]*Session),
		defaultShell: defaultShell,
	}
}

// Create starts a new PTY session. It calls onOutput for stdout data and
// onExit when the process terminates.
// CreateResult holds the result of creating a new session.
type CreateResult struct {
	ID    string
	Shell string
}

func (m *SessionManager) Create(shell string, cols, rows uint16, onOutput OutputCallback, onExit ExitCallback) (CreateResult, error) {
	if shell == "" {
		shell = m.defaultShell
	}

	m.mu.Lock()
	m.nextID++
	id := fmt.Sprintf("s%d", m.nextID)
	m.mu.Unlock()

	p, err := startPTY(shell, cols, rows)
	if err != nil {
		return CreateResult{}, fmt.Errorf("failed to start pty: %w", err)
	}

	sess := &Session{
		ID:  id,
		pty: p,
	}

	m.mu.Lock()
	m.sessions[id] = sess
	m.mu.Unlock()

	// Read goroutine: reads PTY output and sends to callback.
	go func() {
		buf := make([]byte, 4096)
		for {
			n, err := p.Read(buf)
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
		exitCode, _ := p.Wait()

		m.mu.Lock()
		delete(m.sessions, id)
		m.mu.Unlock()

		onExit(id, exitCode)
	}()

	return CreateResult{ID: id, Shell: shell}, nil
}

// Write sends input data to a session's PTY.
func (m *SessionManager) Write(id string, data []byte) error {
	sess := m.get(id)
	if sess == nil {
		return fmt.Errorf("session %s not found", id)
	}
	_, err := sess.pty.Write(data)
	return err
}

// Resize changes the PTY window size.
func (m *SessionManager) Resize(id string, cols, rows uint16) error {
	sess := m.get(id)
	if sess == nil {
		return fmt.Errorf("session %s not found", id)
	}
	return sess.pty.Resize(cols, rows)
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
	sess.pty.Close()

	// Signal the process to terminate.
	sess.pty.Kill()

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
