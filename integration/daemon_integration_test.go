//go:build integration

package integration_test

import (
	"context"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

func unixClient(socket string) *http.Client {
	return &http.Client{Transport: &http.Transport{
		DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, "unix", socket)
		},
	}}
}

func waitForSocket(t *testing.T, socket string) {
	t.Helper()
	for i := 0; i < 100; i++ {
		if _, err := os.Stat(socket); err == nil {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatalf("daemon socket %s never appeared", socket)
}

func TestDaemonSingleInstanceAndShutdown(t *testing.T) {
	binDir, err := os.MkdirTemp("/tmp", "throwntomd-bin")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(binDir) })
	binPath := filepath.Join(binDir, "throwntomd")

	build := exec.Command("go", "build", "-o", binPath, "./cmd/throwntomd")
	build.Dir = ".."
	if out, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build throwntomd: %v\n%s", err, out)
	}

	home, err := os.MkdirTemp("/tmp", "throwntomd-home")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(home) })

	configPath := filepath.Join(home, "config.toml")
	if err := os.WriteFile(configPath, []byte("repeat_secs = 20\nmorning_reminder_pending = false\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	socket := filepath.Join(home, ".config", "throwntom", "daemon.sock")
	sessionPath := filepath.Join(home, ".config", "throwntom", "session.json")

	first := exec.Command(binPath, "--config", configPath)
	first.Env = append(os.Environ(), "HOME="+home)
	var firstStderr strings.Builder
	first.Stderr = &firstStderr
	if err := first.Start(); err != nil {
		t.Fatalf("start first instance: %v", err)
	}
	t.Cleanup(func() { _ = first.Process.Kill() })

	waitForSocket(t, socket)

	client := unixClient(socket)
	resp, err := client.Get("http://throwntomd/v1/state")
	if err != nil {
		t.Fatalf("GET /v1/state over socket: %v", err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d", resp.StatusCode)
	}

	second := exec.Command(binPath, "--config", configPath)
	second.Env = append(os.Environ(), "HOME="+home)
	var secondStderr strings.Builder
	second.Stderr = &secondStderr
	if err := second.Run(); err == nil {
		t.Fatal("expected second instance to exit non-zero")
	}
	if !strings.Contains(secondStderr.String(), "already running") {
		t.Fatalf("expected \"already running\" on stderr, got: %s", secondStderr.String())
	}

	if err := first.Process.Signal(syscall.SIGTERM); err != nil {
		t.Fatalf("signal first instance: %v", err)
	}
	waitErrCh := make(chan error, 1)
	go func() { waitErrCh <- first.Wait() }()
	select {
	case err := <-waitErrCh:
		if err != nil {
			t.Fatalf("expected first instance to exit 0, got: %v (stderr: %s)", err, firstStderr.String())
		}
	case <-time.After(5 * time.Second):
		t.Fatal("first instance did not exit after SIGTERM")
	}

	if _, err := os.Stat(sessionPath); err != nil {
		t.Fatalf("expected session.json to exist: %v", err)
	}
	if _, err := os.Stat(socket); !os.IsNotExist(err) {
		t.Fatalf("expected socket removed after shutdown, stat err: %v", err)
	}
}
