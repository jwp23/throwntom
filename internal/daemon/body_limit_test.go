package daemon

import (
	"net/http/httptest"
	"strings"
	"testing"
)

// Snooze and meeting share the same bound: past a day, a length is far
// likelier to be a typo than an intention (Minutes.maximum in the macOS
// client makes the same call). The daemon is the trust boundary, so it
// enforces this itself rather than relying on any client to have asked first.
func TestTimerSnoozeRejectsMinutesAboveTheBound(t *testing.T) {
	c := newTestCoreWithMorning(t)
	srv := httptest.NewServer(NewHandler(c))
	t.Cleanup(srv.Close)

	resp := postJSON(t, srv.URL+"/v1/timer/snooze", map[string]any{"minutes": 1441})

	if resp.StatusCode != 400 {
		t.Fatalf("status %d, want 400", resp.StatusCode)
	}
	if c.State().SnoozeUntil != nil {
		t.Fatal("a snooze longer than a day was accepted anyway")
	}
}

func TestTimerSnoozeAcceptsExactlyADay(t *testing.T) {
	c := newTestCoreWithMorning(t)
	srv := httptest.NewServer(NewHandler(c))
	t.Cleanup(srv.Close)

	resp := postJSON(t, srv.URL+"/v1/timer/snooze", map[string]any{"minutes": 1440})

	if resp.StatusCode != 200 {
		t.Fatalf("status %d, want 200", resp.StatusCode)
	}
	if c.State().SnoozeUntil == nil {
		t.Fatal("expected snooze_until set")
	}
}

// A body large enough to overflow the daemon's cap must be rejected before
// it is ever handed to json.Decode, not merely refused for its content: an
// unbounded read would allocate the whole thing first regardless of what it
// says. bodyOverCap is far bigger than any of these routes' real requests,
// and bigger than any sane cap the daemon would choose.
func bodyOverCap() string {
	return strings.Repeat("a", 10<<20)
}

func TestBodiedRoutesRejectOversizedBodies(t *testing.T) {
	pad := bodyOverCap()
	cases := []struct {
		name string
		url  string
		body string
	}{
		{"snooze", "/v1/timer/snooze", `{"minutes":10,"pad":"` + pad + `"}`},
		{"meeting", "/v1/timer/meeting", `{"minutes":10,"pad":"` + pad + `"}`},
		{"task", "/v1/tasks", `{"description":"x","pad":"` + pad + `"}`},
		{"command", "/v1/command", `{"line":"x","pad":"` + pad + `"}`},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			srv, _ := newTestServer(t)
			resp := postRaw(t, srv.URL+tc.url, tc.body)
			if resp.StatusCode != 400 {
				t.Fatalf("status %d, want 400", resp.StatusCode)
			}
		})
	}
}
