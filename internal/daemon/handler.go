package daemon

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/jwp23/throwntom/v3/internal/analytics"
	"github.com/jwp23/throwntom/v3/internal/core"
)

type commandRequest struct {
	Line string `json:"line"`
}

type commandResponse struct {
	Message string               `json:"message"`
	Exit    bool                 `json:"exit"`
	Stats   *analytics.Dashboard `json:"stats,omitempty"`
}

type errorResponse struct {
	Error string `json:"error"`
}

type server struct {
	core *core.Core
}

// NewHandler serves the daemon API described in docs/designs/native-macos-client.md.
func NewHandler(c *core.Core) http.Handler {
	s := &server{core: c}
	mux := http.NewServeMux()
	s.registerRoutes(mux)
	mux.HandleFunc("GET /v1/state", s.getState)
	mux.HandleFunc("POST /v1/command", s.postCommand)
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		writeError(w, http.StatusNotFound, errors.New("not found"))
	})
	return mux
}

func (s *server) getState(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, s.core.State())
}

func (s *server) postCommand(w http.ResponseWriter, r *http.Request) {
	var req commandRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, errors.New("invalid JSON body"))
		return
	}
	s.runCommand(w, req.Line)
}

// runCommand executes one command line and writes the outcome; shared by
// the command endpoint and the verb/task routes.
func (s *server) runCommand(w http.ResponseWriter, line string) {
	resp := s.core.Execute(line)
	writeCommandOutcome(w, resp)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, err error) {
	writeJSON(w, status, errorResponse{Error: err.Error()})
}
