package daemon

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/jwp23/throwntom/v3/internal/analytics"
	"github.com/jwp23/throwntom/v3/internal/core"
)

type commandRequest struct {
	Line string `json:"line"`
}

type commandResponse struct {
	Message string               `json:"message"`
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
	mux.HandleFunc("GET /v1/events", s.getEvents)
	return &jsonErrorWriter{handler: mux}
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
	if isQuitLine(line) {
		writeError(w, http.StatusBadRequest, errors.New("quit is not available over the API"))
		return
	}
	resp := s.core.Execute(line)
	writeCommandOutcome(w, resp)
}

// isQuitLine reports whether line asks the core to exit. The API has no notion
// of exiting: running quit would stop the morning reminder and leave the daemon
// serving a half-stopped core.
func isQuitLine(line string) bool {
	fields := strings.Fields(line)
	return len(fields) > 0 && (fields[0] == "quit" || fields[0] == "exit")
}

const contentTypeJSON = "application/json"

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", contentTypeJSON)
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, err error) {
	writeJSON(w, status, errorResponse{Error: err.Error()})
}

// jsonErrorWriter replaces the mux's plain-text 404 and 405 bodies with JSON.
// Routes that answer 404 themselves already write JSON and keep their own,
// more specific message.
type jsonErrorWriter struct {
	handler http.Handler
}

func (j *jsonErrorWriter) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	wrapped := &statusCapturingWriter{ResponseWriter: w}
	j.handler.ServeHTTP(wrapped, r)
	if !wrapped.suppressed {
		return
	}
	switch wrapped.status {
	case http.StatusNotFound:
		writeError(w, http.StatusNotFound, errors.New("not found"))
	case http.StatusMethodNotAllowed:
		writeError(w, http.StatusMethodNotAllowed, errors.New("method not allowed"))
	}
}

type statusCapturingWriter struct {
	http.ResponseWriter
	status     int
	suppressed bool
}

func (s *statusCapturingWriter) WriteHeader(status int) {
	s.status = status
	s.suppressed = isMuxError(status) && s.Header().Get("Content-Type") != contentTypeJSON
	if !s.suppressed {
		s.ResponseWriter.WriteHeader(status)
	}
}

// isMuxError reports the statuses ServeMux itself answers with: an unknown
// path and a path matched by a different method.
func isMuxError(status int) bool {
	return status == http.StatusNotFound || status == http.StatusMethodNotAllowed
}

func (s *statusCapturingWriter) Write(b []byte) (int, error) {
	if s.suppressed {
		return len(b), nil
	}
	return s.ResponseWriter.Write(b)
}

func (s *statusCapturingWriter) Flush() {
	if flusher, ok := s.ResponseWriter.(http.Flusher); ok {
		flusher.Flush()
	}
}
