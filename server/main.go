// Copyright 2026 The MathWorks, Inc.

package main

import (
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"time"
)

// envFlags collects repeatable --env KEY=VALUE flags.
type envFlags []string

func (e *envFlags) String() string { return strings.Join(*e, ",") }
func (e *envFlags) Set(v string) error {
	*e = append(*e, v)
	return nil
}

func main() {
	var (
		token       string
		envVars     envFlags
		idleTimeout time.Duration
	)

	flag.StringVar(&token, "token", "", "authentication token (required)")
	flag.Var(&envVars, "env", "environment variable in KEY=VALUE format (repeatable)")
	flag.DurationVar(&idleTimeout, "idle-timeout", 30*time.Second, "exit after this duration with no connections")
	flag.Parse()

	if token == "" {
		log.Fatal("--token is required")
	}

	// Detect default shell.
	shell := os.Getenv("SHELL")
	if shell == "" {
		shell = "/bin/sh"
	}

	// Build extra environment slice.
	extraEnv := make([]string, len(envVars))
	copy(extraEnv, envVars)

	// Create session manager.
	manager := NewSessionManager(shell, extraEnv)

	// Create HTTP API handler.
	apiHandler := NewAPIHandler(token, manager)

	mux := http.NewServeMux()
	mux.HandleFunc("/api/create", apiHandler.HandleCreate)
	mux.HandleFunc("/api/input", apiHandler.HandleInput)
	mux.HandleFunc("/api/resize", apiHandler.HandleResize)
	mux.HandleFunc("/api/close", apiHandler.HandleClose)
	mux.HandleFunc("/api/poll", apiHandler.HandlePoll)
	mux.HandleFunc("/api/sessions", apiHandler.HandleSessions)
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}

	port := listener.Addr().(*net.TCPAddr).Port
	fmt.Printf("PORT:%d\n", port)

	// Monitor parent PID — exit if parent dies.
	parentPID := os.Getppid()
	go monitorParent(parentPID)

	// Idle timeout based on last API activity.
	go func() {
		time.Sleep(5 * time.Second) // grace period on startup
		ticker := time.NewTicker(5 * time.Second)
		defer ticker.Stop()
		for range ticker.C {
			if time.Since(apiHandler.LastActivity()) >= idleTimeout {
				log.Println("idle timeout reached, shutting down")
				os.Exit(0)
			}
		}
	}()

	log.Fatal(http.Serve(listener, mux))
}

// monitorParent polls the parent PID and exits if it changes to 1 (init)
// which indicates the original parent has died.
func monitorParent(parentPID int) {
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	for range ticker.C {
		if os.Getppid() != parentPID {
			log.Println("parent process died, shutting down")
			os.Exit(0)
		}
	}
}
