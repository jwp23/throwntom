# Daemon state reports which phase a pause interrupted

## Decision

The `State` document (`GET /v1/state` and every SSE frame) carries
`paused_from`: the phase the current pause interrupted (`work`,
`short_break`, `long_break`), or `idle` whenever the timer is not paused.
The value comes straight from `engine.Snapshot.PausedFrom`, which the
engine already tracks to resume correctly.

## Rationale

- The macOS mascot shows the paused phase's pose with its eyes shut, so the
  client has to know whether a pause interrupted work, a short break or a
  long break. `next_stage` cannot tell the two breaks apart.
- Exposing a fact the engine already holds keeps the daemon in its lane:
  it reports state, the client decides how to draw it (ADR-003). Inferring
  the phase client-side from durations or `next_stage` would be a
  presentation layer guessing at timer internals.
- One field, one line in `stateLocked`, decoded by one Swift property; no
  new endpoint and no change to any verb.
