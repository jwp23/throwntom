package daemon

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/jwp23/throwntom/v3/internal/core"
	"github.com/jwp23/throwntom/v3/internal/engine"
)

func postJSONWith(t *testing.T, client *http.Client, url string, body any) *http.Response {
	t.Helper()
	raw, _ := json.Marshal(body)
	resp, err := client.Post(url, "application/json", bytes.NewReader(raw))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = resp.Body.Close() })
	return resp
}

func postJSON(t *testing.T, url string, body any) *http.Response {
	return postJSONWith(t, http.DefaultClient, url, body)
}

func decode[T any](t *testing.T, resp *http.Response) T {
	t.Helper()
	var v T
	if err := json.NewDecoder(resp.Body).Decode(&v); err != nil {
		t.Fatal(err)
	}
	return v
}

func TestGetStateReturnsIdleDocument(t *testing.T) {
	srv, _ := newTestServer(t)
	resp, err := http.Get(srv.URL + "/v1/state")
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != 200 || resp.Header.Get("Content-Type") != "application/json" {
		t.Fatalf("status %d content-type %q", resp.StatusCode, resp.Header.Get("Content-Type"))
	}
	if s := decode[core.State](t, resp); s.State != engine.Idle {
		t.Fatalf("state = %s", s.State)
	}
}

func TestPostCommandRunsCommand(t *testing.T) {
	srv, c := newTestServer(t)
	resp := postJSON(t, srv.URL+"/v1/command", commandRequest{Line: "new-cycle"})
	if resp.StatusCode != 200 {
		t.Fatalf("status %d", resp.StatusCode)
	}
	if r := decode[commandResponse](t, resp); r.Message != "New cycle started -- fresh start!" {
		t.Fatalf("message %q", r.Message)
	}
	if c.State().State != engine.Work {
		t.Fatalf("core state %s", c.State().State)
	}
}

func TestPostCommandUnknownIs400(t *testing.T) {
	srv, _ := newTestServer(t)
	resp := postJSON(t, srv.URL+"/v1/command", commandRequest{Line: "bogus"})
	if resp.StatusCode != 400 {
		t.Fatalf("status %d", resp.StatusCode)
	}
	if e := decode[errorResponse](t, resp); e.Error != "unknown command: bogus" {
		t.Fatalf("error %q", e.Error)
	}
}

func TestPostCommandUsageErrorIs400(t *testing.T) {
	srv, _ := newTestServer(t)
	for _, line := range []string{"snooze bogus", "task done 99", "task bogus"} {
		resp := postJSON(t, srv.URL+"/v1/command", commandRequest{Line: line})
		if resp.StatusCode != 400 {
			t.Fatalf("%q: status %d", line, resp.StatusCode)
		}
	}
}

func TestPostCommandRefusedTransitionIs409(t *testing.T) {
	srv, _ := newTestServer(t)
	resp := postJSON(t, srv.URL+"/v1/command", commandRequest{Line: "pause"})
	if resp.StatusCode != 409 {
		t.Fatalf("status %d", resp.StatusCode)
	}
}

func TestPostCommandRejectsQuit(t *testing.T) {
	for line, want := range map[string]string{
		"quit":     "quit is not available over the API",
		"exit":     "exit is not available over the API",
		"quit now": "quit is not available over the API",
	} {
		c := newTestCoreWithMorning(t)
		srv := httptest.NewServer(NewHandler(c))
		resp := postJSON(t, srv.URL+"/v1/command", commandRequest{Line: line})
		if resp.StatusCode != 400 {
			t.Fatalf("%q: status %d", line, resp.StatusCode)
		}
		if e := decode[errorResponse](t, resp); e.Error != want {
			t.Fatalf("%q: error %q, want %q", line, e.Error, want)
		}
		if !c.State().MorningPending {
			t.Fatalf("%q: morning reminder was stopped", line)
		}
		srv.Close()
	}
}

func TestPostCommandRejectsTestSound(t *testing.T) {
	srv, _ := newTestServer(t)
	resp := postJSON(t, srv.URL+"/v1/command", commandRequest{Line: "test-sound"})
	if resp.StatusCode != 400 {
		t.Fatalf("status %d", resp.StatusCode)
	}
	want := "test-sound is not available over the API: the daemon plays no sound"
	if e := decode[errorResponse](t, resp); e.Error != want {
		t.Fatalf("error %q, want %q", e.Error, want)
	}
}

// The refusal is a fact about the notifier this daemon holds, not about the
// API. daemon.Run accepts any notifier, so one that sounds must get the sound
// it asked for rather than a message saying the daemon plays none.
func TestPostCommandPlaysTestSoundWhenTheNotifierSounds(t *testing.T) {
	played := make(chan string, 1)
	c := newTestCoreWithNotifier(t, soundingNotifier{played: played})
	srv := httptest.NewServer(NewHandler(c))
	t.Cleanup(srv.Close)

	resp := postJSON(t, srv.URL+"/v1/command", commandRequest{Line: "test-sound"})
	if resp.StatusCode != 200 {
		t.Fatalf("status %d", resp.StatusCode)
	}
	if got := decode[commandResponse](t, resp).Message; got != "Sound test played." {
		t.Fatalf("message %q", got)
	}
	select {
	case name := <-played:
		if name != "test" {
			t.Fatalf("played %q, want the test sound", name)
		}
	default:
		t.Fatal("no sound was played")
	}
}

// TestUnavailableOverAPI covers the ways a refused command can be written:
// the guard splits the line the way the core does, so arguments and
// surrounding space must not get one past it, and every other line must
// still reach the core.
func TestUnavailableOverAPI(t *testing.T) {
	s := &server{core: newTestCore(t)}
	refused := []string{
		"quit", "exit", "quit now", "  quit  ",
		"test-sound", "test-sound now", "  test-sound  ",
	}
	for _, line := range refused {
		if err := s.unavailableOverAPI(line); err == nil {
			t.Errorf("%q was accepted", line)
		}
	}
	for _, line := range []string{"", "   ", "start", "status", "task add write it up", "TEST-SOUND"} {
		if err := s.unavailableOverAPI(line); err != nil {
			t.Errorf("%q was refused: %v", line, err)
		}
	}
}

func TestPostCommandBadJSONIs400(t *testing.T) {
	srv, _ := newTestServer(t)
	resp, err := http.Post(srv.URL+"/v1/command", "application/json", bytes.NewReader([]byte("{")))
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != 400 {
		t.Fatalf("status %d", resp.StatusCode)
	}
}

func TestUnknownRouteIs404JSON(t *testing.T) {
	srv, _ := newTestServer(t)
	resp, err := http.Get(srv.URL + "/v1/nope")
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != 404 || resp.Header.Get("Content-Type") != "application/json" {
		t.Fatalf("status %d content-type %q", resp.StatusCode, resp.Header.Get("Content-Type"))
	}
}

func TestWrongMethodIs405JSON(t *testing.T) {
	srv, _ := newTestServer(t)
	resp := postJSON(t, srv.URL+"/v1/state", commandRequest{Line: "test"})
	if resp.StatusCode != 405 || resp.Header.Get("Content-Type") != "application/json" {
		t.Fatalf("status %d content-type %q", resp.StatusCode, resp.Header.Get("Content-Type"))
	}
	if resp.Header.Get("Allow") == "" {
		t.Fatal("Allow header missing")
	}
	if e := decode[errorResponse](t, resp); e.Error != "method not allowed" {
		t.Fatalf("error %q", e.Error)
	}
}
