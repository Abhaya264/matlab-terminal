// Copyright 2026 The MathWorks, Inc.

package main

import (
	"bytes"
	"io"
	"sync"
	"testing"
	"time"
)

// mockPTY implements the ptyProcess interface for testing.
type mockPTY struct {
	mu       sync.Mutex
	input    bytes.Buffer // data written via Write()
	output   bytes.Buffer // data returned by Read()
	closed   bool
	exitCode int
	exitCh   chan struct{} // closed when Wait should return
	lastCols uint16       // last cols passed to Resize
	lastRows uint16       // last rows passed to Resize
}

func newMockPTY() *mockPTY {
	return &mockPTY{exitCh: make(chan struct{})}
}

func (m *mockPTY) Read(p []byte) (int, error) {
	m.mu.Lock()
	if m.output.Len() > 0 {
		n, err := m.output.Read(p)
		m.mu.Unlock()
		return n, err
	}
	if m.closed {
		m.mu.Unlock()
		return 0, io.EOF
	}
	m.mu.Unlock()
	// Block until closed or data available.
	<-m.exitCh
	return 0, io.EOF
}

func (m *mockPTY) Write(p []byte) (int, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.closed {
		return 0, io.ErrClosedPipe
	}
	return m.input.Write(p)
}

func (m *mockPTY) Resize(cols, rows uint16) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.closed {
		return io.ErrClosedPipe
	}
	m.lastCols = cols
	m.lastRows = rows
	return nil
}

func (m *mockPTY) Close() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if !m.closed {
		m.closed = true
		close(m.exitCh)
	}
	return nil
}

func (m *mockPTY) Wait() (int, error) {
	<-m.exitCh
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.exitCode, nil
}

func (m *mockPTY) pushOutput(data []byte) {
	m.mu.Lock()
	m.output.Write(data)
	m.mu.Unlock()
}

// insertSession manually registers a session into the manager for unit testing
// without calling startPTY.
func insertSession(m *SessionManager, id string, pty ptyProcess) *Session {
	sess := &Session{
		ID:         id,
		pty:        pty,
		scrollback: make([]byte, 0, 4096),
	}
	m.mu.Lock()
	m.sessions[id] = sess
	m.mu.Unlock()
	return sess
}

// --- NewSessionManager tests ---

func TestNewSessionManager(t *testing.T) {
	sm := NewSessionManager("/bin/bash")
	if sm == nil {
		t.Fatal("NewSessionManager returned nil")
	}
	if sm.defaultShell != "/bin/bash" {
		t.Errorf("defaultShell = %q, want /bin/bash", sm.defaultShell)
	}
	if sm.Count() != 0 {
		t.Errorf("Count = %d, want 0", sm.Count())
	}
}

// --- Count and IDs tests ---

func TestSessionManager_CountAndIDs_Empty(t *testing.T) {
	sm := NewSessionManager("sh")
	if sm.Count() != 0 {
		t.Errorf("Count = %d, want 0", sm.Count())
	}
	ids := sm.IDs()
	if len(ids) != 0 {
		t.Errorf("IDs = %v, want empty", ids)
	}
}

func TestSessionManager_CountAndIDs_WithSessions(t *testing.T) {
	sm := NewSessionManager("sh")
	insertSession(sm, "s1", newMockPTY())
	insertSession(sm, "s2", newMockPTY())

	if sm.Count() != 2 {
		t.Errorf("Count = %d, want 2", sm.Count())
	}
	ids := sm.IDs()
	if len(ids) != 2 {
		t.Errorf("len(IDs) = %d, want 2", len(ids))
	}
	idSet := map[string]bool{}
	for _, id := range ids {
		idSet[id] = true
	}
	if !idSet["s1"] || !idSet["s2"] {
		t.Errorf("IDs = %v, want [s1, s2]", ids)
	}
}

// --- Write tests ---

func TestSessionManager_Write_NonexistentSession(t *testing.T) {
	sm := NewSessionManager("sh")
	err := sm.Write("bogus", []byte("hello"))
	if err == nil {
		t.Error("Write to nonexistent session should return error")
	}
}

func TestSessionManager_Write_Success(t *testing.T) {
	sm := NewSessionManager("sh")
	mock := newMockPTY()
	insertSession(sm, "s1", mock)

	err := sm.Write("s1", []byte("hello"))
	if err != nil {
		t.Fatalf("Write returned error: %v", err)
	}

	mock.mu.Lock()
	got := mock.input.String()
	mock.mu.Unlock()
	if got != "hello" {
		t.Errorf("pty received %q, want %q", got, "hello")
	}
}

func TestSessionManager_Write_ClosedPTY(t *testing.T) {
	sm := NewSessionManager("sh")
	mock := newMockPTY()
	insertSession(sm, "s1", mock)
	mock.Close()

	err := sm.Write("s1", []byte("hello"))
	if err == nil {
		t.Error("Write to closed PTY should return error")
	}
}

// --- Resize tests ---

func TestSessionManager_Resize_NonexistentSession(t *testing.T) {
	sm := NewSessionManager("sh")
	err := sm.Resize("bogus", 80, 24)
	if err == nil {
		t.Error("Resize on nonexistent session should return error")
	}
}

func TestSessionManager_Resize_Success(t *testing.T) {
	sm := NewSessionManager("sh")
	mock := newMockPTY()
	insertSession(sm, "s1", mock)

	err := sm.Resize("s1", 120, 40)
	if err != nil {
		t.Fatalf("Resize returned error: %v", err)
	}

	mock.mu.Lock()
	cols, rows := mock.lastCols, mock.lastRows
	mock.mu.Unlock()
	if cols != 120 {
		t.Errorf("cols = %d, want 120", cols)
	}
	if rows != 40 {
		t.Errorf("rows = %d, want 40", rows)
	}
}

func TestSessionManager_Resize_ClosedPTY(t *testing.T) {
	sm := NewSessionManager("sh")
	mock := newMockPTY()
	insertSession(sm, "s1", mock)
	mock.Close()

	err := sm.Resize("s1", 80, 24)
	if err == nil {
		t.Error("Resize on closed PTY should return error")
	}
}

// --- Close tests ---

func TestSessionManager_Close_NonexistentSession(t *testing.T) {
	sm := NewSessionManager("sh")
	err := sm.Close("bogus")
	if err == nil {
		t.Error("Close on nonexistent session should return error")
	}
}

func TestSessionManager_Close_Success(t *testing.T) {
	sm := NewSessionManager("sh")
	mock := newMockPTY()
	insertSession(sm, "s1", mock)

	err := sm.Close("s1")
	if err != nil {
		t.Fatalf("Close returned error: %v", err)
	}

	mock.mu.Lock()
	closed := mock.closed
	mock.mu.Unlock()
	if !closed {
		t.Error("PTY was not closed")
	}
}

func TestSessionManager_Close_DoubleClose(t *testing.T) {
	sm := NewSessionManager("sh")
	mock := newMockPTY()
	insertSession(sm, "s1", mock)

	err := sm.Close("s1")
	if err != nil {
		t.Fatalf("first Close returned error: %v", err)
	}

	// Second close should be idempotent (session.closed is true).
	err = sm.Close("s1")
	if err != nil {
		t.Errorf("second Close returned error: %v", err)
	}
}

// --- Scrollback tests ---

func TestSessionManager_Scrollback_NonexistentSession(t *testing.T) {
	sm := NewSessionManager("sh")
	data := sm.Scrollback("bogus")
	if data != nil {
		t.Errorf("Scrollback for nonexistent session = %v, want nil", data)
	}
}

func TestSessionManager_Scrollback_Empty(t *testing.T) {
	sm := NewSessionManager("sh")
	insertSession(sm, "s1", newMockPTY())

	data := sm.Scrollback("s1")
	if len(data) != 0 {
		t.Errorf("Scrollback = %q, want empty", data)
	}
}

func TestSessionManager_Scrollback_WithData(t *testing.T) {
	sm := NewSessionManager("sh")
	sess := insertSession(sm, "s1", newMockPTY())

	sess.appendScrollback([]byte("hello "))
	sess.appendScrollback([]byte("world"))

	data := sm.Scrollback("s1")
	if string(data) != "hello world" {
		t.Errorf("Scrollback = %q, want %q", data, "hello world")
	}
}

func TestSessionManager_Scrollback_ReturnsCopy(t *testing.T) {
	sm := NewSessionManager("sh")
	sess := insertSession(sm, "s1", newMockPTY())
	sess.appendScrollback([]byte("original"))

	data := sm.Scrollback("s1")
	data[0] = 'X' // mutate the returned slice

	fresh := sm.Scrollback("s1")
	if string(fresh) != "original" {
		t.Errorf("Scrollback was mutated: got %q, want %q", fresh, "original")
	}
}

// --- appendScrollback tests ---

func TestAppendScrollback_Basic(t *testing.T) {
	sess := &Session{scrollback: make([]byte, 0, 4096)}
	sess.appendScrollback([]byte("hello"))
	sess.appendScrollback([]byte(" world"))

	sess.mu.Lock()
	got := string(sess.scrollback)
	sess.mu.Unlock()

	if got != "hello world" {
		t.Errorf("scrollback = %q, want %q", got, "hello world")
	}
}

func TestAppendScrollback_Cap(t *testing.T) {
	sess := &Session{scrollback: make([]byte, 0, 4096)}

	// Fill with more than scrollbackCap (128 KB).
	chunk := bytes.Repeat([]byte("A"), 64*1024) // 64 KB
	sess.appendScrollback(chunk)
	sess.appendScrollback(chunk) // 128 KB total
	sess.appendScrollback([]byte("TAIL"))

	sess.mu.Lock()
	got := sess.scrollback
	sess.mu.Unlock()

	if len(got) > scrollbackCap {
		t.Errorf("scrollback len = %d, want <= %d", len(got), scrollbackCap)
	}
	// The tail should be preserved.
	if !bytes.HasSuffix(got, []byte("TAIL")) {
		t.Error("scrollback did not keep the tail after cap trim")
	}
}

func TestAppendScrollback_ExactCap(t *testing.T) {
	sess := &Session{scrollback: make([]byte, 0, 4096)}

	// Fill exactly to cap.
	data := bytes.Repeat([]byte("B"), scrollbackCap)
	sess.appendScrollback(data)

	sess.mu.Lock()
	got := len(sess.scrollback)
	sess.mu.Unlock()

	if got != scrollbackCap {
		t.Errorf("scrollback len = %d, want %d", got, scrollbackCap)
	}
}

func TestAppendScrollback_ConcurrentSafe(t *testing.T) {
	sess := &Session{scrollback: make([]byte, 0, 4096)}

	var wg sync.WaitGroup
	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			sess.appendScrollback([]byte("data"))
		}()
	}
	wg.Wait()

	sess.mu.Lock()
	got := len(sess.scrollback)
	sess.mu.Unlock()

	expected := 100 * 4 // 100 goroutines * 4 bytes
	if got != expected {
		t.Errorf("scrollback len = %d, want %d", got, expected)
	}
}

// --- get tests ---

func TestSessionManager_Get_Exists(t *testing.T) {
	sm := NewSessionManager("sh")
	insertSession(sm, "s1", newMockPTY())

	sess := sm.get("s1")
	if sess == nil {
		t.Error("get returned nil for existing session")
	}
	if sess.ID != "s1" {
		t.Errorf("session ID = %q, want %q", sess.ID, "s1")
	}
}

func TestSessionManager_Get_NotExists(t *testing.T) {
	sm := NewSessionManager("sh")
	sess := sm.get("bogus")
	if sess != nil {
		t.Errorf("get returned %v for nonexistent session, want nil", sess)
	}
}

// --- Create integration test (uses real PTY via startPTY) ---

func TestSessionManager_Create_DefaultShell(t *testing.T) {
	sm := NewSessionManager(defaultShell())

	var outputReceived sync.WaitGroup
	outputReceived.Add(1)
	outputOnce := sync.Once{}

	result, err := sm.Create("", 80, 24,
		func(sessionID string, data []byte) {
			outputOnce.Do(func() { outputReceived.Done() })
		},
		func(sessionID string, exitCode int) {},
	)
	if err != nil {
		t.Fatalf("Create failed: %v", err)
	}
	if result.ID == "" {
		t.Error("Create returned empty ID")
	}
	if result.Shell == "" {
		t.Error("Create returned empty Shell")
	}

	// Verify the session was registered.
	if sm.Count() != 1 {
		t.Errorf("Count = %d, want 1", sm.Count())
	}

	// Wait for some output (shell prompt) with timeout.
	done := make(chan struct{})
	go func() {
		outputReceived.Wait()
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		// Some CI shells may not produce a prompt; that's okay.
	}

	sm.Close(result.ID)
}

func TestSessionManager_Create_IDsAreUnique(t *testing.T) {
	sm := NewSessionManager(defaultShell())

	r1, err := sm.Create("", 80, 24,
		func(string, []byte) {},
		func(string, int) {},
	)
	if err != nil {
		t.Fatalf("Create 1 failed: %v", err)
	}

	r2, err := sm.Create("", 80, 24,
		func(string, []byte) {},
		func(string, int) {},
	)
	if err != nil {
		t.Fatalf("Create 2 failed: %v", err)
	}

	if r1.ID == r2.ID {
		t.Error("two sessions got the same ID")
	}

	sm.Close(r1.ID)
	sm.Close(r2.ID)
}
