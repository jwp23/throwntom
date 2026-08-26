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
	for _, line := range []string{"quit", "exit", "quit now"} {
		c := newTestCoreWithMorning(t)
		srv := httptest.NewServer(NewHandler(c))
		resp := postJSON(t, srv.URL+"/v1/command", commandRequest{Line: line})
		if resp.StatusCode != 400 {
			t.Fatalf("%q: status %d", line, resp.StatusCode)
		}
		if e := decode[errorResponse](t, resp); e.Error != "quit is not available over the API" {
			t.Fatalf("%q: error %q", line, e.Error)
		}
		if !c.State().MorningPending {
			t.Fatalf("%q: morning reminder was stopped", line)
		}
		srv.Close()
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
