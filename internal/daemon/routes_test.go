package daemon

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

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
