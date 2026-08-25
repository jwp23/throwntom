package daemon

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"github.com/jwp23/throwntom/v3/internal/core"
)

var timerVerbs = map[string]bool{"start": true, "confirm": true, "pause": true, "resume": true, "skip-today": true, "new-cycle": true}

func (s *server) registerRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /v1/timer/snooze", s.postSnooze)
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

func (s *server) postSnooze(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Minutes int `json:"minutes"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Minutes <= 0 {
		writeError(w, http.StatusBadRequest, errors.New("minutes must be a positive integer"))
		return
	}
	s.runCommand(w, "snooze "+strconv.Itoa(body.Minutes))
}

func (s *server) getTasks(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, s.core.Tasks())
}

func (s *server) postTask(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Description string `json:"description"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || strings.TrimSpace(body.Description) == "" {
		writeError(w, http.StatusBadRequest, errors.New("description is required"))
		return
	}
	resp := s.core.Execute("task add " + strings.TrimSpace(body.Description))
	if resp.Error != "" {
		writeError(w, http.StatusConflict, errors.New(resp.Error))
		return
	}
	active := s.core.Tasks().Active
	writeJSON(w, http.StatusCreated, active[len(active)-1])
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
		status := http.StatusConflict
		if strings.HasPrefix(resp.Error, "unknown command") {
			status = http.StatusBadRequest
		}
		writeError(w, status, errors.New(resp.Error))
		return
	}
	writeJSON(w, http.StatusOK, commandResponse{Message: resp.Message, Exit: resp.Exit, Stats: resp.Stats})
}
