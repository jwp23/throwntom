package daemon

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"

	"github.com/jwp23/throwntom/v3/internal/core"
)

func (s *server) getEvents(w http.ResponseWriter, r *http.Request) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		writeError(w, http.StatusInternalServerError, errors.New("streaming unsupported"))
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.WriteHeader(http.StatusOK)

	states, cancel := s.core.Subscribe()
	defer cancel()
	for {
		select {
		case <-r.Context().Done():
			return
		case st, open := <-states:
			if !open {
				return
			}
			if err := writeState(w, st); err != nil {
				return
			}
			flusher.Flush()
		}
	}
}

func writeState(w http.ResponseWriter, st core.State) error {
	data, err := json.Marshal(st)
	if err != nil {
		return err
	}
	_, err = fmt.Fprintf(w, "event: state\ndata: %s\n\n", data)
	return err
}
