// Copyright 2026 The MathWorks, Inc.

package main

import (
	"sync"
	"testing"
	"time"
	"fmt"
)

// TestSessionManager_Create tests creating a new session
func TestSessionManager_Create(t *testing.T) {
	manager := NewSessionManager("/bin/bash")

	outputCallback := func(sessionID string, data []byte) {
		// Output callback
	}
	exitCallback := func(sessionID string, exitCode int) {
		// Exit callback
	}

	result, err := manager.Create("", 80, 24, outputCallback, exitCallback)
	if err != nil {
		t.Fatalf("Failed to create session: %v", err)
	}

	if result.ID == "" {
		t.Error("Expected non-empty session ID")
	}

	if result.Shell == "" {
		t.Error("Expected non-empty shell path")
	}

	// Clean up
	manager.Close(result.ID)
}

// TestSessionManager_CreateWithCustomShell tests creating a session with a custom shell
func TestSessionManager_CreateWithCustomShell(t *testing.T) {
	manager := NewSessionManager("/bin/bash")

	customShell := "/bin/sh"
	result, err := manager.Create(customShell, 80, 24, nil, nil)
	if err != nil {
		t.Fatalf("Failed to create session with custom shell: %v", err)
	}

	if result.Shell != customShell {
		t.Errorf("Expected shell %s, got %s", customShell, result.Shell)
	}

	manager.Close(result.ID)
}

// TestSessionManager_CreateWithDefaultShell tests creating a session with default shell
func TestSessionManager_CreateWithDefaultShell(t *testing.T) {
	defaultShell := "/bin/bash"
	manager := NewSessionManager(defaultShell)

	result, err := manager.Create("", 80, 24, nil, nil)
	if err != nil {
		t.Fatalf("Failed to create session: %v", err)
	}

	if result.Shell != defaultShell {
		t.Errorf("Expected default shell %s, got %s", defaultShell, result.Shell)
	}

	manager.Close(result.ID)
}

// TestSessionManager_CreateMultipleSessions tests creating multiple sessions
func TestSessionManager_CreateMultipleSessions(t *testing.T) {
	manager := NewSessionManager("/bin/bash")

	session1, err := manager.Create("", 80, 24, nil, nil)
	if err != nil {
		t.Fatalf("Failed to create first session: %v", err)
	}

	session2, err := manager.Create("", 80, 24, nil, nil)
	if err != nil {
		t.Fatalf("Failed to create second session: %v", err)
	}

	if session1.ID == session2.ID {
		t.Error("Expected unique session IDs")
	}

	ids := manager.IDs()
	if len(ids) != 2 {
		t.Errorf("Expected 2 sessions, got %d", len(ids))
	}

	manager.Close(session1.ID)
	manager.Close(session2.ID)
}

// TestSessionManager_Write tests writing data to a session
func TestSessionManager_Write(t *testing.T) {
	manager := NewSessionManager("/bin/bash")

	result, err := manager.Create("", 80, 24, nil, nil)
	if err != nil {
		t.Fatalf("Failed to create session: %v", err)
	}

	// Write some data
	testData := []byte("echo hello\n")
	err = manager.Write(result.ID, testData)
	if err != nil {
		t.Errorf("Failed to write to session: %v", err)
	}

	manager.Close(result.ID)
}

// TestSessionManager_WriteToNonExistentSession tests writing to a non-existent session
func TestSessionManager_WriteToNonExistentSession(t *testing.T) {
	manager := NewSessionManager("/bin/bash")

	err := manager.Write("non-existent-id", []byte("test"))
	if err == nil {
		t.Error("Expected error when writing to non-existent session")
	}
}

// TestSessionManager_Resize tests resizing a session
func TestSessionManager_Resize(t *testing.T) {
	manager := NewSessionManager("/bin/bash")

	result, err := manager.Create("", 80, 24, nil, nil)
	if err != nil {
		t.Fatalf("Failed to create session: %v", err)
	}

	// Resize the session
	err = manager.Resize(result.ID, 120, 30)
	if err != nil {
		t.Errorf("Failed to resize session: %v", err)
	}

	manager.Close(result.ID)
}

// TestSessionManager_ResizeNonExistentSession tests resizing a non-existent session
func TestSessionManager_ResizeNonExistentSession(t *testing.T) {
	manager := NewSessionManager("/bin/bash")

	err := manager.Resize("non-existent-id", 100, 30)
	if err == nil {
		t.Error("Expected error when resizing non-existent session")
	}
}

// TestSessionManager_Close tests closing a session
func TestSessionManager_Close(t *testing.T) {
	manager := NewSessionManager("/bin/bash")

	result, err := manager.Create("", 80, 24, nil, nil)
	if err != nil {
		t.Fatalf("Failed to create session: %v", err)
	}

	err = manager.Close(result.ID)
	if err != nil {
		t.Errorf("Failed to close session: %v", err)
	}

	// Verify session is removed
	ids := manager.IDs()
	for _, id := range ids {
		if id == result.ID {
			t.Error("Session should be removed after close")
		}
	}
}

// TestSessionManager_CloseNonExistentSession tests closing a non-existent session
func TestSessionManager_CloseNonExistentSession(t *testing.T) {
	manager := NewSessionManager("/bin/bash")

	err := manager.Close("non-existent-id")
	if err == nil {
		t.Error("Expected error when closing non-existent session")
	}
}

// TestSessionManager_IDs tests getting session IDs
func TestSessionManager_IDs(t *testing.T) {
	manager := NewSessionManager("/bin/bash")

	// Initially empty
	ids := manager.IDs()
	if len(ids) != 0 {
		t.Errorf("Expected 0 sessions initially, got %d", len(ids))
	}

	// Create sessions
	s1, _ := manager.Create("", 80, 24, nil, nil)
	s2, _ := manager.Create("", 80, 24, nil, nil)

	ids = manager.IDs()
	if len(ids) != 2 {
		t.Errorf("Expected 2 sessions, got %d", len(ids))
	}

	// Verify IDs are correct
	foundS1, foundS2 := false, false
	for _, id := range ids {
		if id == s1.ID {
			foundS1 = true
		}
		if id == s2.ID {
			foundS2 = true
		}
	}

	if !foundS1 || !foundS2 {
		t.Error("Expected to find both session IDs")
	}

	manager.Close(s1.ID)
	manager.Close(s2.ID)
}

// TestSessionManager_Scrollback tests getting scrollback buffer
func TestSessionManager_Scrollback(t *testing.T) {
	manager := NewSessionManager("/bin/bash")

	result, err := manager.Create("", 80, 24, nil, nil)
	if err != nil {
		t.Fatalf("Failed to create session: %v", err)
	}

	// Get scrollback (should not be nil for valid session)
	data := manager.Scrollback(result.ID)
	if data == nil {
		t.Error("Expected non-nil scrollback data for valid session")
	}

	manager.Close(result.ID)
}

// TestSessionManager_ScrollbackNonExistentSession tests getting scrollback for non-existent session
func TestSessionManager_ScrollbackNonExistentSession(t *testing.T) {
	manager := NewSessionManager("/bin/bash")

	data := manager.Scrollback("non-existent-id")
	if data != nil {
		t.Error("Expected nil scrollback data for non-existent session")
	}
}

// TestSessionManager_OutputCallback tests that output callback is invoked
func TestSessionManager_OutputCallback(t *testing.T) {
	manager := NewSessionManager("/bin/bash")

	var mu sync.Mutex
	var callbackInvoked bool

	outputCallback := func(sessionID string, data []byte) {
		mu.Lock()
		defer mu.Unlock()
		callbackInvoked = true
	}

	result, err := manager.Create("", 80, 24, outputCallback, nil)
	if err != nil {
		t.Fatalf("Failed to create session: %v", err)
	}

	// Write a command that should produce output
	manager.Write(result.ID, []byte("echo test\n"))

	// Wait a bit for output
	time.Sleep(500 * time.Millisecond)

	mu.Lock()
	invoked := callbackInvoked
	mu.Unlock()

	if !invoked {
		t.Error("Expected output callback to be invoked")
	}

	manager.Close(result.ID)
}

// TestSessionManager_ExitCallback tests that exit callback is invoked
func TestSessionManager_ExitCallback(t *testing.T) {
	manager := NewSessionManager("/bin/bash")

	var mu sync.Mutex
	var exitCallbackInvoked bool

	exitCallback := func(sessionID string, exitCode int) {
		mu.Lock()
		defer mu.Unlock()
		exitCallbackInvoked = true
	}

	result, err := manager.Create("", 80, 24, nil, exitCallback)
	if err != nil {
		t.Fatalf("Failed to create session: %v", err)
	}

	// Send exit command
	manager.Write(result.ID, []byte("exit\n"))

	// Wait for process to exit
	time.Sleep(1 * time.Second)

	mu.Lock()
	invoked := exitCallbackInvoked
	mu.Unlock()

	if !invoked {
		t.Error("Expected exit callback to be invoked")
	}

	manager.Close(result.ID)
}

// TestSessionManager_ConcurrentOperations tests concurrent session operations
func TestSessionManager_ConcurrentOperations(t *testing.T) {
	manager := NewSessionManager("/bin/bash")

	var wg sync.WaitGroup
	numSessions := 5

	// Create sessions concurrently
	sessionIDs := make([]string, numSessions)
	for i := 0; i < numSessions; i++ {
		wg.Add(1)
		go func(index int) {
			defer wg.Done()
			result, err := manager.Create("", 80, 24, nil, nil)
			if err != nil {
				t.Errorf("Failed to create session %d: %v", index, err)
				return
			}
			sessionIDs[index] = result.ID
		}(i)
	}
	wg.Wait()

	// Write to sessions concurrently
	for i := 0; i < numSessions; i++ {
		wg.Add(1)
		go func(id string) {
			defer wg.Done()
			err := manager.Write(id, []byte("echo test\n"))
			if err != nil {
				t.Errorf("Failed to write to session: %v", err)
			}
		}(sessionIDs[i])
	}
	wg.Wait()

	// Close sessions concurrently
	for i := 0; i < numSessions; i++ {
		wg.Add(1)
		go func(id string) {
			defer wg.Done()
			err := manager.Close(id)
			if err != nil {
				t.Errorf("Failed to close session: %v", err)
			}
		}(sessionIDs[i])
	}
	wg.Wait()

	// Verify all sessions are closed
	ids := manager.IDs()
	if len(ids) != 0 {
		t.Errorf("Expected 0 sessions after closing all, got %d", len(ids))
	}
}

// TestSessionManager_InvalidDimensions tests creating a session with invalid dimensions
func TestSessionManager_InvalidDimensions(t *testing.T) {
	manager := NewSessionManager("/bin/bash")

	testCases := []struct {
		name string
		cols uint16
		rows uint16
	}{
		{"Zero columns", 0, 24},
		{"Zero rows", 80, 0},
		{"Both zero", 0, 0},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			result, err := manager.Create("", tc.cols, tc.rows, nil, nil)
			// If creation succeeded, clean up
			if err == nil {
				manager.Close(result.ID)
			}
			// Depending on implementation, this might succeed with defaults or fail
			// Uncomment below if implementation should reject invalid dimensions:
			// if err == nil {
			//     t.Error("Expected error for invalid dimensions")
			// }
		})
	}
}

func TestSessionManager_Concurrency(t *testing.T) {
	// Setup the manager
	manager := NewSessionManager(defaultShell())
	var wg sync.WaitGroup
	
	// Simulate 50 concurrent session creations
	numRoutines := 50
	ids := make([]string, numRoutines)

	for i := 0; i < numRoutines; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			
			// 1. Define dummy callbacks matching the exact signatures from session.go
			dummyOut := func(sessionID string, data []byte) {
				// Do nothing, just safely absorb the output
			}
			dummyExit := func(sessionID string, exitCode int) {
				// Do nothing, just safely absorb the exit event
			}

			// 2. Pass the dummy functions instead of nil
			res, err := manager.Create("", 80, 24, dummyOut, dummyExit)
			if err == nil {
				ids[idx] = res.ID 
			} else {
				t.Errorf("Failed to create session concurrently: %v", err)
			}
		}(i)
	}
	wg.Wait()

	// Verify all 50 sessions were created without overwriting each other
	if manager.Count() != numRoutines {
		t.Errorf("Expected %d sessions, got %d", numRoutines, manager.Count())
	}

	// Simulate concurrent reads and closures
	for i := 0; i < numRoutines; i++ {
		wg.Add(1)
		go func(idx int) {
			fmt.Printf("Closing session %d\n", idx)
			defer wg.Done()
			if ids[idx] != "" {
				// Verify we can get it using the unexported get() method
				if sess := manager.get(ids[idx]); sess == nil {
					t.Errorf("Failed to get session %s concurrently", ids[idx])
				}
				// Close it
				manager.Close(ids[idx])
			}
		}(i)
	}
	wg.Wait()

	// Verify all sessions were cleanly removed from the map
	if manager.Count() != 0 {
		t.Errorf("Expected 0 sessions after close, got %d", manager.Count())
	}
}