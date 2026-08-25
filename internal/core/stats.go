package core

import (
	"fmt"

	"github.com/jwp23/throwntom/v3/internal/analytics"
	"github.com/jwp23/throwntom/v3/internal/eventlog"
)

func (c *Core) handleStats(_ []string) commandResult {
	events, err := eventlog.ReadAll(c.eventsPath)
	if err != nil {
		return commandResult{err: fmt.Errorf("read events: %w", err)}
	}
	dash := analytics.Compute(events, c.now())
	return commandResult{stats: &dash}
}
