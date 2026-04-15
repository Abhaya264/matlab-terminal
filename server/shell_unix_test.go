// Copyright 2026 The MathWorks, Inc.

//go:build !windows

package main

import (
	"os"
	"testing"
)

func TestDefaultShell_Unix(t *testing.T) {
	// Save and restore original SHELL
	original := os.Getenv("SHELL")
	defer os.Setenv("SHELL", original)

	t.Run("returns SHELL when set", func(t *testing.T) {
		os.Setenv("SHELL", "/bin/zsh")
		if got := defaultShell(); got != "/bin/zsh" {
			t.Errorf("got %q, want /bin/zsh", got)
		}
	})

	t.Run("returns /bin/sh when SHELL empty", func(t *testing.T) {
		os.Setenv("SHELL", "")
		if got := defaultShell(); got != "/bin/sh" {
			t.Errorf("got %q, want /bin/sh", got)
		}
	})

	t.Run("returns /bin/sh when SHELL unset", func(t *testing.T) {
		os.Unsetenv("SHELL")
		if got := defaultShell(); got != "/bin/sh" {
			t.Errorf("got %q, want /bin/sh", got)
		}
	})
}