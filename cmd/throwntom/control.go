package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
)

type daemonControlResponse struct {
	StatusLine     string `json:"status_line"`
	MorningPending bool   `json:"morning_pending"`
	Message        string `json:"message"`
	Error          string `json:"error"`
	Exit           bool   `json:"exit"`
}

func defaultSocketPath() string {
	runtimeDir := os.Getenv("XDG_RUNTIME_DIR")
	if strings.TrimSpace(runtimeDir) == "" {
		runtimeDir = os.TempDir()
	}
	return filepath.Join(runtimeDir, "throwntom.sock")
}

func sendControlCommand(socketPath string, command string) (daemonControlResponse, error) {
	conn, err := net.Dial("unix", socketPath)
	if err != nil {
		return daemonControlResponse{}, fmt.Errorf("connect to daemon socket %q: %w", socketPath, err)
	}
	defer conn.Close()

	writer := bufio.NewWriter(conn)
	if _, err := writer.WriteString(strings.TrimSpace(command) + "\n"); err != nil {
		return daemonControlResponse{}, fmt.Errorf("write command: %w", err)
	}
	if err := writer.Flush(); err != nil {
		return daemonControlResponse{}, fmt.Errorf("flush command: %w", err)
	}

	var resp daemonControlResponse
	decoder := json.NewDecoder(conn)
	if err := decoder.Decode(&resp); err != nil {
		return daemonControlResponse{}, fmt.Errorf("decode daemon response: %w", err)
	}
	return resp, nil
}
