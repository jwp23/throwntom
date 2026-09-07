package daemon

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"

	"github.com/jwp23/throwntom/v3/internal/core"
)

// Snooze, meeting and lunch are absent: each carries a body and has a route
// of its own. Unsnooze takes no argument, so it is an ordinary verb.
var timerVerbs = map[string]bool{"start": true, "confirm": true, "pause": true, "resume": true, "skip": true, "skip-today": true, "new-cycle": true, "unsnooze": true}

func (s *server) registerRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /v1/timer/snooze", s.postSnooze)
	mux.HandleFunc("POST /v1/timer/meeting", s.postMeeting)
	mux.HandleFunc("POST /v1/timer/lunch", s.postLunch)
	mux.HandleFunc("POST /v1/timer/{verb}", s.postTimerVerb)
	mux.HandleFunc("GET /v1/tasks", s.getTasks)
	mux.HandleFunc("POST /v1/tasks", s.postTask)
	mux.HandleFunc("POST /v1/tasks/clear-completed", func(w http.ResponseWriter, _ *http.Request) { s.runCommand(w, "task clear") })
	mux.HandleFunc("POST /v1/tasks/{id}/complete", func(w http.ResponseWriter, r *http.Request) { s.taskByID(w, r, "done") })
	mux.HandleFunc("DELETE /v1/tasks/{id}", func(w http.ResponseWriter, r *http.Request) { s.taskByID(w, r, "remove") })
	mux.HandleFunc("GET /v1/stats", s.getStats)
}

func (s *server) postTimerVerb(w http.ResponseWriter, r *http.Request) {
	verb := r.PathValue("verb")
	if !timerVerbs[verb] {
		writeError(w, http.StatusNotFound, fmt.Errorf("unknown timer verb: %s", verb))
		return
	}
	s.runNonInteractive(w, verb)
}

// runNonInteractive runs a verb and, if it opened the task-focus prompt,
// answers it with an empty line so the API is non-interactive: after
// Execute(verb), if s.core.FocusPromptPending() { resp = s.core.Execute("") }.
func (s *server) runNonInteractive(w http.ResponseWriter, line string) {
	resp := s.core.Execute(line)
	if s.core.FocusPromptPending() {
		resp = s.core.Execute("")
	}
	writeCommandOutcome(w, resp)
}

// maxRequestBodyBytes caps every bodied route's request body before it is
// decoded, so a body many times larger than any of these routes' fields
// could ever need is rejected by the reader rather than fully allocated for
// json.Decode to then refuse. Generous for a task description, which is the
// largest field these routes take.
const maxRequestBodyBytes = 64 * 1024

// decodeBody wraps r's body in the shared size cap, decodes exactly one JSON
// value into dst, and requires nothing to follow it: a second Decode call
// must hit io.EOF. Without this, a decoder that stops once dst is filled
// would leave trailing bytes unread, so MaxBytesReader's cap would bound
// only what the first value needed rather than everything a route accepts.
// Every bodied route shares this contract, so one reader enforces it for all
// of them rather than each restating it.
func decodeBody(w http.ResponseWriter, r *http.Request, dst any) error {
	r.Body = http.MaxBytesReader(w, r.Body, maxRequestBodyBytes)
	dec := json.NewDecoder(r.Body)
	if err := dec.Decode(dst); err != nil {
		return err
	}
	var extra json.RawMessage
	if dec.Decode(&extra) != io.EOF {
		return errors.New("body must contain exactly one JSON value")
	}
	return nil
}

// maxMeetingMinutes is the longest meeting or snooze this route will accept,
// in the minutes the body speaks in. It is derived from the one rule rather
// than restating it, so the routes and the command line cannot drift apart.
// The macOS client refuses the same length before asking (Minutes.maximum),
// but a client's rule is not the daemon's: this is the trust boundary, and it
// holds the bound too.
var maxMeetingMinutes = int(core.MaxMeetingDuration.Minutes())

// readMinutesBody decodes a {"minutes": N} body shared by snooze and
// meeting: both ask for nothing but a length, and both refuse the same
// range for the same reason, so one reader validates for both rather than
// each restating the rule.
func readMinutesBody(w http.ResponseWriter, r *http.Request) (int, bool) {
	var body struct {
		Minutes int `json:"minutes"`
	}
	if err := decodeBody(w, r, &body); err != nil || body.Minutes <= 0 || body.Minutes > maxMeetingMinutes {
		writeError(w, http.StatusBadRequest, fmt.Errorf("minutes must be between 1 and %d", maxMeetingMinutes))
		return 0, false
	}
	return body.Minutes, true
}

func (s *server) postSnooze(w http.ResponseWriter, r *http.Request) {
	minutes, ok := readMinutesBody(w, r)
	if !ok {
		return
	}
	s.runCommand(w, "snooze "+strconv.Itoa(minutes))
}

// postMeeting starts a meeting of the minutes given. Like snooze it takes a
// body rather than a bare verb, because a meeting with no length has nothing
// to run for.
func (s *server) postMeeting(w http.ResponseWriter, r *http.Request) {
	minutes, ok := readMinutesBody(w, r)
	if !ok {
		return
	}
	s.runCommand(w, "meeting "+strconv.Itoa(minutes))
}

// postLunch starts lunch, with or without an explicit length. Unlike meeting,
// lunch has a config default, so its body is optional: none at all keeps
// today's behavior, the same bare "lunch" command the wildcard route used to
// serve. The body is read in full up front rather than handed straight to
// decodeBody, because an absent body and a malformed one both hit decodeBody's
// io.EOF check the same way -- only a look at the raw bytes first can tell
// "no minutes given" from "minutes given badly".
func (s *server) postLunch(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxRequestBodyBytes))
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	// A JSON null body is what a Go client sends for "no options" (json.Marshal(nil)),
	// so it is read the same way a truly empty body is: neither names a length.
	if trimmed := bytes.TrimSpace(body); len(trimmed) == 0 || string(trimmed) == "null" {
		s.runNonInteractive(w, "lunch")
		return
	}
	r.Body = io.NopCloser(bytes.NewReader(body))
	minutes, ok := readMinutesBody(w, r)
	if !ok {
		return
	}
	s.runNonInteractive(w, "lunch "+strconv.Itoa(minutes))
}

func (s *server) getTasks(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, s.core.Tasks())
}

func (s *server) postTask(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Description string `json:"description"`
	}
	if err := decodeBody(w, r, &body); err != nil {
		writeError(w, http.StatusBadRequest, errors.New("description is required"))
		return
	}
	tk, err := s.core.AddTask(body.Description)
	if err != nil {
		writeError(w, http.StatusBadRequest, errors.New("description is required"))
		return
	}
	writeJSON(w, http.StatusCreated, tk)
}

func (s *server) taskByID(w http.ResponseWriter, r *http.Request, action string) {
	id, err := strconv.Atoi(r.PathValue("id"))
	if err != nil {
		writeError(w, http.StatusBadRequest, errors.New("task id must be an integer"))
		return
	}
	for pos, tk := range s.core.Tasks().Active {
		if tk.ID == id {
			s.runCommand(w, fmt.Sprintf("task %s %d", action, pos+1))
			return
		}
	}
	writeError(w, http.StatusNotFound, fmt.Errorf("no active task with id %d", id))
}

func (s *server) getStats(w http.ResponseWriter, _ *http.Request) {
	resp := s.core.Execute("stats")
	if resp.Error != "" || resp.Stats == nil {
		writeError(w, http.StatusInternalServerError, errors.New(resp.Error))
		return
	}
	writeJSON(w, http.StatusOK, resp.Stats)
}

func writeCommandOutcome(w http.ResponseWriter, resp core.Response) {
	if resp.Error != "" {
		status := http.StatusBadRequest
		if resp.ErrorKind == core.ErrorRefused {
			status = http.StatusConflict
		}
		writeError(w, status, errors.New(resp.Error))
		return
	}
	writeJSON(w, http.StatusOK, commandResponse{Message: resp.Message, Stats: resp.Stats})
}
