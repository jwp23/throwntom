# Focused Tasks Design

## Goal

Allow users to manage a lightweight task list and select focused tasks for each pomodoro work session. Tasks persist across restarts. Completed tasks are hidden but reviewable for daily summary.

## Architecture

New `internal/task` package owns task data and persistence. The `App` layer holds a reference to the task store and tracks per-pomodoro focus state. Daemon core handles command dispatch and the focus prompt flow.

The engine (state machine) is untouched — tasks are an orthogonal concern.

```
TaskStore (interface)
  ^
  |
FileStore (implementation, persists to JSON)
  ^
  |
App (holds store + focus state)
  ^
  |
DaemonCore (commands + focus prompt orchestration)
  ^
  |
Bubble Tea UI (renders focus display + prompt)
```

Future: the FileStore can be swapped for an implementation that talks to an external todo CLI.

## Task Package

### Interface

```go
type TaskStore interface {
    Add(description string) (Task, error)
    Complete(id int) error
    Remove(id int) error
    Active() []Task
    Completed() []Task
    ClearCompleted() error
}
```

### Data

```go
type Task struct {
    ID          int
    Description string
    Done        bool
    CreatedAt   time.Time
    CompletedAt time.Time
}
```

### FileStore

- Location: `~/.config/throwntom/tasks.json`
- JSON format with `next_id` for auto-incrementing IDs (never reused)
- Written on every mutation
- Created automatically on first `task add` if absent

```json
{
  "next_id": 4,
  "tasks": [
    {"id": 1, "description": "refactor auth", "done": false, "created_at": "2026-03-05T09:00:00Z", "completed_at": null},
    {"id": 2, "description": "write tests", "done": true, "created_at": "2026-03-05T09:01:00Z", "completed_at": "2026-03-05T10:30:00Z"}
  ]
}
```

### Numbering

`Active()` returns uncompleted tasks. User-facing commands reference 1-based sequential position in the active list. The store maps positions back to IDs internally.

## Focus State

Tracked in the `App` layer, in-memory only (not persisted):

```go
focusedTasks []task.Task  // ordered by priority (index 0 = top)
```

- Set during the focus prompt at pomodoro start
- Modifiable during a work session (focus, unfocus, up, down, done)
- Cleared when pomodoro ends (stop, idle, break transition)
- Tasks completed in a previous pomodoro remain available in the active list for re-selection

## Focus Prompt

Triggers when entering a Work phase:
1. User types `start` (manual start)
2. User types `confirm` and next phase is Work (after a break)

If no active tasks exist, the prompt is skipped and the pomodoro starts immediately.

### Prompt UI

Temporarily replaces the normal header/status area:

```
  Select tasks for this pomodoro:
  1) refactor auth
  2) update docs
  3) fix login bug

  Focused: 1, 3

  (numbers to toggle, a <desc> to add, enter to start):
```

- Typing a number toggles that task's focus on/off
- Typing `a <description>` adds a new task and auto-focuses it
- The "Focused" line updates after each input
- Enter confirms selection and starts the pomodoro
- Empty enter with no focused tasks starts with no focus (skip)

## Work Session Display

During a work session with focused tasks, a vertical focus list appears above the status line in priority order:

```
  Focus:
    1. refactor auth
    2. fix login bug
  status: pomodoro | 15:23 | today's pomodoros=2 | pomodoros=2/4
  message: task added
  command>
```

When no tasks are focused, the focus section is hidden (display identical to today).

## Commands

All task commands use the `task` prefix. Available anytime unless noted.

| Command | Context | Description |
|---|---|---|
| `task add <desc>` | anytime | Add a new task |
| `task done <n>` | anytime | Mark task as completed |
| `task remove <n>` | anytime | Delete a task entirely |
| `task list` | anytime | Show active tasks |
| `task completed` | anytime | Show completed tasks |
| `task clear` | anytime | Clear all completed tasks |
| `task focus <n>` | work session | Add task to current focus |
| `task unfocus <n>` | work session | Remove task from focus |
| `task up <n>` | work session | Move focused task up in priority |
| `task down <n>` | work session | Move focused task down in priority |

### Numbering context

- `task done`, `task remove`, `task focus`: numbers reference the global active task list
- `task unfocus`, `task up`, `task down`: numbers reference the focused list's priority order
- `task done` also works with focused list numbers during a work session

## Help Menu

All task commands added to the `?` toggleable help:

```
Task commands:
  task add <desc>     Add a task
  task done <n>       Complete a task
  task remove <n>     Delete a task
  task list           Show active tasks
  task completed      Show completed tasks
  task clear          Clear completed
  task focus <n>      Focus on task (work session)
  task unfocus <n>    Remove focus (work session)
  task up/down <n>    Reorder focused tasks
```

## Daemon Core Integration

### Prompt state

```go
// In daemonCore
pendingFocusPrompt bool
```

When `pendingFocusPrompt` is true:
- Status area shows the task selection prompt
- Input is interpreted as task selection (numbers, `a <desc>`) or enter to start
- After selection, pomodoro starts and `pendingFocusPrompt` clears

### Command dispatch

New handlers registered in `daemonCore.handlers` map for each `task *` subcommand. The `task` prefix handler parses the subcommand and delegates.

## Cross-Mode Support

All three modes (local, daemon, shell) share `daemonCore` logic, so task commands and the focus prompt work everywhere automatically. The focus prompt state is part of the daemon response, so shell mode can render it.

## Risks and Edge Cases

- **Concurrent access**: FileStore writes on every mutation. Single-user app, no locking needed.
- **Empty task file**: Handle gracefully — treat as empty list, create on first write.
- **Corrupt JSON**: Return error, don't silently lose data.
- **Task numbering stability**: Active list ordering is by ID (creation order). Numbers only shift when tasks are completed or removed.
- **Focus prompt in daemon mode**: Shell/control clients send commands; the prompt state must be part of the response so the UI knows to render the prompt.
- **Focus prompt skip**: If user sends `start` via `ctl` (control mode), there's no interactive prompt. Start immediately with no focus.
