package daemon

import (
	"bufio"
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/core"
	"github.com/jwp23/throwntom/v3/internal/engine"
)

// readEvent reads one SSE message and decodes its data line.
func readEvent(t *testing.T, br *bufio.Reader) core.State {
	t.Helper()
	var data string
	for {
		line, err := br.ReadString('\n')
		if err != nil {
			t.Fatalf("read event: %v", err)
		}
		line = strings.TrimRight(line, "\n")
		switch {
		case strings.HasPrefix(line, "data: "):
			data = strings.TrimPrefix(line, "data: ")
		case line == "" && data != "":
			var s core.State
			if err := json.Unmarshal([]byte(data), &s); err != nil {
				t.Fatal(err)
			}
			return s
		}
	}
}

func TestEventsStreamsInitialAndSubsequentStates(t *testing.T) {
	srv, c := newTestServer(t)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, srv.URL+"/v1/events", nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = resp.Body.Close() }()
	if ct := resp.Header.Get("Content-Type"); !strings.HasPrefix(ct, "text/event-stream") {
		t.Fatalf("content-type %q", ct)
	}
	br := bufio.NewReader(resp.Body)
	if s := readEvent(t, br); s.State != engine.Idle {
		t.Fatalf("initial state %s", s.State)
	}
	c.Execute("new-cycle")
	if s := readEvent(t, br); s.State != engine.Work {
		t.Fatalf("after start %s", s.State)
	}
}

func TestEventsEndsWhenClientDisconnects(t *testing.T) {
	srv, c := newTestServer(t)
	ctx, cancel := context.WithCancel(context.Background())
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, srv.URL+"/v1/events", nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	readEvent(t, bufio.NewReader(resp.Body))
	cancel()
	_ = resp.Body.Close()
	// After disconnect the subscriber must be gone: publishing must not block or panic.
	done := make(chan struct{})
	go func() { c.Execute("new-cycle"); close(done) }()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("Execute blocked after subscriber disconnect")
	}
}
