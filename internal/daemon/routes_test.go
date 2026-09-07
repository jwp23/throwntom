package daemon

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/analytics"
	"github.com/jwp23/throwntom/v3/internal/core"
	"github.com/jwp23/throwntom/v3/internal/engine"
	"github.com/jwp23/throwntom/v3/internal/task"
)

func TestTimerStartSkipsFocusPrompt(t *testing.T) {
	srv, c := newTestServer(t)
	resp := postJSON(t, srv.URL+"/v1/timer/start", nil)
	if resp.StatusCode != 200 {
		t.Fatalf("status %d", resp.StatusCode)
	}
	if c.FocusPromptPending() {
		t.Fatal("daemon must not leave the core in the focus prompt")
	}
	if c.State().State != engine.Work {
		t.Fatalf("state %s", c.State().State)
	}
}

func TestTimerPauseWhenIdleIs409(t *testing.T) {
	srv, _ := newTestServer(t)
	if resp := postJSON(t, srv.URL+"/v1/timer/pause", nil); resp.StatusCode != 409 {
		t.Fatalf("status %d", resp.StatusCode)
	}
}

func TestTimerSnoozeRequiresMinutes(t *testing.T) {
	srv, c := newTestServer(t)
	if resp := postJSON(t, srv.URL+"/v1/timer/snooze", map[string]int{}); resp.StatusCode != 400 {
		t.Fatalf("status %d", resp.StatusCode)
	}
	if resp := postJSON(t, srv.URL+"/v1/timer/snooze", map[string]int{"minutes": 0}); resp.StatusCode != 400 {
		t.Fatalf("status %d", resp.StatusCode)
	}
	// Snooze at idle (no morning pending, no reminder to snooze) is refused.
	if resp := postJSON(t, srv.URL+"/v1/timer/snooze", map[string]int{"minutes": 10}); resp.StatusCode != 409 {
		t.Fatalf("status %d", resp.StatusCode)
	}
	if c.State().SnoozeUntil != nil {
		t.Fatal("unexpected snooze_until set at idle")
	}
}

func TestTimerSnoozeWithMorningPending(t *testing.T) {
	c := newTestCoreWithMorning(t)
	srv := httptest.NewServer(NewHandler(c))
	t.Cleanup(srv.Close)

	// Verify morning is pending before snooze
	if !c.State().MorningPending {
		t.Fatal("expected morning reminder pending")
	}
	if resp := postJSON(t, srv.URL+"/v1/timer/snooze", map[string]int{"minutes": 10}); resp.StatusCode != 200 {
		t.Fatalf("snooze status %d", resp.StatusCode)
	}
	// Snooze with morning pending sets SnoozeUntil
	if c.State().SnoozeUntil == nil {
		t.Fatal("expected snooze_until set when morning pending")
	}
}

func TestTimerUnknownVerbIs404(t *testing.T) {
	srv, _ := newTestServer(t)
	resp := postJSON(t, srv.URL+"/v1/timer/dance", nil)
	if resp.StatusCode != 404 {
		t.Fatalf("status %d", resp.StatusCode)
	}
	if e := decode[errorResponse](t, resp); !strings.Contains(e.Error, "dance") {
		t.Fatalf("error %q does not name the verb", e.Error)
	}
}

func TestTaskCompleteUnknownIDKeeps404Message(t *testing.T) {
	srv, _ := newTestServer(t)
	resp := postJSON(t, srv.URL+"/v1/tasks/999/complete", nil)
	if resp.StatusCode != 404 {
		t.Fatalf("status %d", resp.StatusCode)
	}
	if e := decode[errorResponse](t, resp); !strings.Contains(e.Error, "999") {
		t.Fatalf("error %q does not name the task id", e.Error)
	}
}

func TestTasksCRUD(t *testing.T) {
	srv, _ := newTestServer(t)
	created := postJSON(t, srv.URL+"/v1/tasks", map[string]string{"description": "write tests"})
	if created.StatusCode != 201 {
		t.Fatalf("create status %d", created.StatusCode)
	}
	tk := decode[task.Task](t, created)

	listResp, err := http.Get(srv.URL + "/v1/tasks")
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = listResp.Body.Close() }()
	list := decode[core.TaskList](t, listResp)
	if len(list.Active) != 1 || list.Active[0].ID != tk.ID {
		t.Fatalf("active = %+v", list.Active)
	}

	if resp := postJSON(t, srv.URL+"/v1/tasks/"+itoa(tk.ID)+"/complete", nil); resp.StatusCode != 200 {
		t.Fatalf("complete status %d", resp.StatusCode)
	}
	if resp := postJSON(t, srv.URL+"/v1/tasks/999/complete", nil); resp.StatusCode != 404 {
		t.Fatalf("missing id status %d", resp.StatusCode)
	}
	if resp := postJSON(t, srv.URL+"/v1/tasks/clear-completed", nil); resp.StatusCode != 200 {
		t.Fatalf("clear status %d", resp.StatusCode)
	}
	listResp, _ = http.Get(srv.URL + "/v1/tasks")
	if list = decode[core.TaskList](t, listResp); len(list.Active)+len(list.Completed) != 0 {
		t.Fatalf("expected empty lists, got %+v", list)
	}
}

func TestTasksEmptyListsEncodeAsArrays(t *testing.T) {
	srv, _ := newTestServer(t)
	resp, err := http.Get(srv.URL + "/v1/tasks")
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = resp.Body.Close() }()
	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	body := string(raw)
	for _, want := range []string{`"active":[]`, `"completed":[]`} {
		if !strings.Contains(body, want) {
			t.Fatalf("expected body to contain %s, got %s", want, body)
		}
	}
}

func TestTasksDelete(t *testing.T) {
	srv, _ := newTestServer(t)
	tk := decode[task.Task](t, postJSON(t, srv.URL+"/v1/tasks", map[string]string{"description": "x"}))
	req, _ := http.NewRequest(http.MethodDelete, srv.URL+"/v1/tasks/"+itoa(tk.ID), nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != 200 {
		t.Fatalf("delete status %d", resp.StatusCode)
	}
}

func TestTasksCreateRejectsEmpty(t *testing.T) {
	srv, _ := newTestServer(t)
	if resp := postJSON(t, srv.URL+"/v1/tasks", map[string]string{"description": " "}); resp.StatusCode != 400 {
		t.Fatalf("status %d", resp.StatusCode)
	}
}

func TestStatsReturnsDashboard(t *testing.T) {
	srv, _ := newTestServer(t)
	postJSON(t, srv.URL+"/v1/timer/new-cycle", nil)
	resp, err := http.Get(srv.URL + "/v1/stats")
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != 200 {
		t.Fatalf("status %d", resp.StatusCode)
	}
	if d := decode[analytics.Dashboard](t, resp); d.Today.Pomodoros != 0 {
		t.Fatalf("today pomodoros = %d", d.Today.Pomodoros)
	}
}

func itoa(i int) string { return strconv.Itoa(i) }

func TestSkipVerbIsRouted(t *testing.T) {
	srv, _ := newTestServer(t)
	postJSON(t, srv.URL+"/v1/timer/start", nil)
	if resp := postJSON(t, srv.URL+"/v1/timer/skip", nil); resp.StatusCode != 200 {
		t.Fatalf("expected skip to be an accepted timer verb, got status %d", resp.StatusCode)
	}
}

func TestTimerUnsnoozeClearsTheDeadline(t *testing.T) {
	c := newTestCoreWithMorning(t)
	srv := httptest.NewServer(NewHandler(c))
	t.Cleanup(srv.Close)

	if resp := postJSON(t, srv.URL+"/v1/timer/snooze", map[string]int{"minutes": 30}); resp.StatusCode != 200 {
		t.Fatalf("snooze status %d", resp.StatusCode)
	}
	if c.State().SnoozeUntil == nil {
		t.Fatal("expected snooze_until set before cancelling it")
	}
	if resp := postJSON(t, srv.URL+"/v1/timer/unsnooze", nil); resp.StatusCode != 200 {
		t.Fatalf("unsnooze status %d", resp.StatusCode)
	}
	if c.State().SnoozeUntil != nil {
		t.Fatal("expected snooze_until cleared by unsnooze")
	}
	if !c.State().MorningPending {
		t.Fatal("expected the morning reminder to still be outstanding")
	}
}

func TestTimerUnsnoozeWithNoSnoozeIs409(t *testing.T) {
	c := newTestCoreWithMorning(t)
	srv := httptest.NewServer(NewHandler(c))
	t.Cleanup(srv.Close)

	if resp := postJSON(t, srv.URL+"/v1/timer/unsnooze", nil); resp.StatusCode != 409 {
		t.Fatalf("status %d", resp.StatusCode)
	}
}

func TestTimerLunchIsAcceptedFromAnyState(t *testing.T) {
	srv, c := newTestServer(t)

	if resp := postJSON(t, srv.URL+"/v1/timer/lunch", nil); resp.StatusCode != 200 {
		t.Fatalf("lunch from idle: status %d", resp.StatusCode)
	}
	if c.State().State != engine.Lunch {
		t.Fatalf("state %s, want lunch", c.State().State)
	}
	if resp := postJSON(t, srv.URL+"/v1/timer/lunch", nil); resp.StatusCode != 200 {
		t.Fatalf("lunch during lunch: status %d", resp.StatusCode)
	}
}

// A lunch route with no body at all keeps today's config-default behavior --
// the bodyless call the macOS app and every existing script already make.
func TestTimerLunchWithNoBodyUsesTheConfiguredDefault(t *testing.T) {
	srv, c := newTestServer(t)

	resp := postRaw(t, srv.URL+"/v1/timer/lunch", "")

	if resp.StatusCode != 200 {
		t.Fatalf("status %d", resp.StatusCode)
	}
	if c.State().State != engine.Lunch {
		t.Fatalf("state %s, want lunch", c.State().State)
	}
}

// A lunch route given an explicit length runs for that length instead of the
// configured one, the way meeting always has.
func TestTimerLunchWithMinutesRunsForThatLength(t *testing.T) {
	srv, c := newTestServer(t)

	resp := postJSON(t, srv.URL+"/v1/timer/lunch", map[string]any{"minutes": 30})

	if resp.StatusCode != 200 {
		t.Fatalf("status %d", resp.StatusCode)
	}
	snap := c.State()
	if snap.State != engine.Lunch {
		t.Fatalf("state %s, want lunch", snap.State)
	}
	if remaining := time.Until(*snap.PhaseEndAt); remaining < 29*time.Minute || remaining > 30*time.Minute {
		t.Fatalf("lunch has %s left, want ~30m", remaining)
	}
}

func TestTimerLunchRejectsALengthItCannotUse(t *testing.T) {
	for _, body := range []map[string]any{
		{"minutes": 0},
		{"minutes": -5},
	} {
		srv, c := newTestServer(t)

		resp := postJSON(t, srv.URL+"/v1/timer/lunch", body)

		if resp.StatusCode != 400 {
			t.Fatalf("lunch %v: status %d, want 400", body, resp.StatusCode)
		}
		if c.State().State == engine.Lunch {
			t.Fatalf("lunch %v: a rejected lunch started anyway", body)
		}
	}
}

// The daemon is the trust boundary, so it enforces the same day-long bound on
// lunch that it does on meeting, rather than trusting a client to have asked
// first.
func TestTimerLunchRejectsALengthLongerThanADay(t *testing.T) {
	srv, c := newTestServer(t)

	resp := postJSON(t, srv.URL+"/v1/timer/lunch", map[string]any{"minutes": 1441})

	if resp.StatusCode != 400 {
		t.Fatalf("status %d, want 400", resp.StatusCode)
	}
	if c.State().State == engine.Lunch {
		t.Fatal("a lunch longer than a day started anyway")
	}
}

// A malformed body must not be silently treated as "no body" -- only a truly
// empty one falls back to the configured default.
func TestTimerLunchRejectsAMalformedBody(t *testing.T) {
	srv, c := newTestServer(t)

	resp := postRaw(t, srv.URL+"/v1/timer/lunch", `{"minutes":`)

	if resp.StatusCode != 400 {
		t.Fatalf("status %d, want 400", resp.StatusCode)
	}
	if c.State().State == engine.Lunch {
		t.Fatal("a malformed lunch body was accepted anyway")
	}
}
