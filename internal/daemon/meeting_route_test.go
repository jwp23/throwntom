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

// The daemon is the trust boundary, so the length is bounded here rather than
// only in the client that happens to be asking. A meeting longer than a day is
// a typo, and one accepted at face value parks the timer in a phase the user
// then has to notice and undo.
func TestTimerMeetingRejectsALengthLongerThanADay(t *testing.T) {
	srv, c := newTestServer(t)

	resp := postJSON(t, srv.URL+"/v1/timer/meeting", map[string]any{"minutes": 1441})

	if resp.StatusCode != 400 {
		t.Fatalf("status %d, want 400", resp.StatusCode)
	}
	if c.State().State == engine.Meeting {
		t.Fatal("a meeting longer than a day started anyway")
	}
}

func TestTimerMeetingAcceptsALengthOfExactlyADay(t *testing.T) {
	srv, c := newTestServer(t)

	resp := postJSON(t, srv.URL+"/v1/timer/meeting", map[string]any{"minutes": 1440})

	if resp.StatusCode != 200 {
		t.Fatalf("status %d, want 200", resp.StatusCode)
	}
	if c.State().State != engine.Meeting {
		t.Fatalf("state %s, want meeting", c.State().State)
	}
}

// The bare verb has no length to run for, so it must not be reachable as one.
func TestTimerMeetingIsNotABareVerb(t *testing.T) {
	srv, _ := newTestServer(t)

	if resp := postJSON(t, srv.URL+"/v1/timer/meeting", nil); resp.StatusCode == 200 {
		t.Fatal("a meeting with no length was accepted")
	}
}
