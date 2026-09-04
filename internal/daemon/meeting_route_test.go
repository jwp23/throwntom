package daemon

import (
	"testing"

	"github.com/jwp23/throwntom/v3/internal/engine"
)

// A meeting carries a length, so it has a route of its own the way snooze
// does rather than being one more bare verb.

func TestTimerMeetingStartsAMeetingOfTheMinutesGiven(t *testing.T) {
	srv, c := newTestServer(t)

	resp := postJSON(t, srv.URL+"/v1/timer/meeting", map[string]any{"minutes": 30})

	if resp.StatusCode != 200 {
		t.Fatalf("meeting: status %d", resp.StatusCode)
	}
	if c.State().State != engine.Meeting {
		t.Fatalf("state %s, want meeting", c.State().State)
	}
}

func TestTimerMeetingRejectsALengthItCannotUse(t *testing.T) {
	for _, body := range []map[string]any{
		{"minutes": 0},
		{"minutes": -5},
		{},
	} {
		srv, c := newTestServer(t)

		resp := postJSON(t, srv.URL+"/v1/timer/meeting", body)

		if resp.StatusCode != 400 {
			t.Fatalf("meeting %v: status %d, want 400", body, resp.StatusCode)
		}
		if c.State().State == engine.Meeting {
			t.Fatalf("meeting %v: a rejected meeting started anyway", body)
		}
	}
}

// The bare verb has no length to run for, so it must not be reachable as one.
func TestTimerMeetingIsNotABareVerb(t *testing.T) {
	srv, _ := newTestServer(t)

	if resp := postJSON(t, srv.URL+"/v1/timer/meeting", nil); resp.StatusCode == 200 {
		t.Fatal("a meeting with no length was accepted")
	}
}
