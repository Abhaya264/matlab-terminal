// Copyright 2026 The MathWorks, Inc.

package main

import (
	"os"
	"runtime"
	"testing"
)

func TestDefaultShell_ReturnsNonEmpty(t *testing.T) {
	shell := defaultShell()
	if shell == "" {
		t.Error("defaultShell() returned empty string")
	}
}

func TestDefaultShell_RespectsEnvVar(t *testing.T) {
	if runtime.GOOS == "windows" {
		original := os.Getenv("COMSPEC")
		t.Setenv("COMSPEC", `C:\Windows\System32\cmd.exe`)
		shell := defaultShell()
		if shell != `C:\Windows\System32\cmd.exe` {
			t.Errorf("defaultShell() = %q, want C:\\Windows\\System32\\cmd.exe", shell)
		}
		if original != "" {
			os.Setenv("COMSPEC", original)
		}
	} else {
		original := os.Getenv("SHELL")
		t.Setenv("SHELL", "/bin/zsh")
		shell := defaultShell()
		if shell != "/bin/zsh" {
			t.Errorf("defaultShell() = %q, want /bin/zsh", shell)
		}
		if original != "" {
			os.Setenv("SHELL", original)
		}
	}
}

func TestDefaultShell_Fallback(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Setenv("COMSPEC", "")
		shell := defaultShell()
		if shell != "cmd.exe" {
			t.Errorf("defaultShell() with empty COMSPEC = %q, want cmd.exe", shell)
		}
	} else {
		t.Setenv("SHELL", "")
		shell := defaultShell()
		if shell != "/bin/sh" {
			t.Errorf("defaultShell() with empty SHELL = %q, want /bin/sh", shell)
		}
	}
}
