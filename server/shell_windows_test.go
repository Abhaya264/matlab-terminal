// Copyright 2026 The MathWorks, Inc.

//go:build windows

package main

import (
	"os"
	"testing"
)

func TestDefaultShell_Windows(t *testing.T) {
	// Save and restore original COMSPEC
	original := os.Getenv("COMSPEC")
	defer os.Setenv("COMSPEC", original)

	t.Run("returns COMSPEC when set", func(t *testing.T) {
		os.Setenv("COMSPEC", "C:\\Windows\\System32\\cmd.exe")
		if got := defaultShell(); got != "C:\\Windows\\System32\\cmd.exe" {
			t.Errorf("got %q, want C:\\Windows\\System32\\cmd.exe", got)
		}
	})

	t.Run("returns cmd.exe when COMSPEC empty", func(t *testing.T) {
		os.Setenv("COMSPEC", "")
		if got := defaultShell(); got != "cmd.exe" {
			t.Errorf("got %q, want cmd.exe", got)
		}
	})

	t.Run("returns cmd.exe when COMSPEC unset", func(t *testing.T) {
		os.Unsetenv("COMSPEC")
		if got := defaultShell(); got != "cmd.exe" {
			t.Errorf("got %q, want cmd.exe", got)
		}
	})
}