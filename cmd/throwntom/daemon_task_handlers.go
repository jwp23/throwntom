package main

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/jwp23/throwntom/internal/task"
)

func (d *daemonCore) handleTask(parts []string) daemonCommandResult {
	if d.tasks == nil {
		return daemonCommandResult{err: fmt.Errorf("task store not initialized")}
	}
	if len(parts) < 2 {
		return daemonCommandResult{err: fmt.Errorf("usage: task <subcommand>")}
	}
	switch parts[1] {
	case "add":
		return d.handleTaskAdd(parts)
	case "done":
		return d.handleTaskDone(parts)
	case "remove":
		return d.handleTaskRemove(parts)
	case "list":
		return d.handleTaskList()
	case "completed":
		return d.handleTaskCompleted()
	case "clear":
		return d.handleTaskClear()
	default:
		return daemonCommandResult{err: fmt.Errorf("unknown task subcommand: %s", parts[1])}
	}
}

func (d *daemonCore) handleTaskAdd(parts []string) daemonCommandResult {
	if len(parts) < 3 {
		return daemonCommandResult{err: fmt.Errorf("usage: task add <description>")}
	}
	desc := strings.Join(parts[2:], " ")
	t, err := d.tasks.Add(desc)
	if err != nil {
		return daemonCommandResult{err: fmt.Errorf("add task: %w", err)}
	}
	return daemonCommandResult{message: fmt.Sprintf("added task %d: %s", t.ID, t.Description)}
}

func (d *daemonCore) handleTaskDone(parts []string) daemonCommandResult {
	if len(parts) < 3 {
		return daemonCommandResult{err: fmt.Errorf("usage: task done <n>")}
	}
	pos, err := strconv.Atoi(parts[2])
	if err != nil {
		return daemonCommandResult{err: fmt.Errorf("invalid task number: %s", parts[2])}
	}
	id, err := d.tasks.ActiveTaskID(pos)
	if err != nil {
		return daemonCommandResult{err: fmt.Errorf("task done: %w", err)}
	}
	if err := d.tasks.Complete(id); err != nil {
		return daemonCommandResult{err: fmt.Errorf("task done: %w", err)}
	}
	return daemonCommandResult{message: fmt.Sprintf("task %d completed", pos)}
}

func (d *daemonCore) handleTaskRemove(parts []string) daemonCommandResult {
	if len(parts) < 3 {
		return daemonCommandResult{err: fmt.Errorf("usage: task remove <n>")}
	}
	pos, err := strconv.Atoi(parts[2])
	if err != nil {
		return daemonCommandResult{err: fmt.Errorf("invalid task number: %s", parts[2])}
	}
	id, err := d.tasks.ActiveTaskID(pos)
	if err != nil {
		return daemonCommandResult{err: fmt.Errorf("task remove: %w", err)}
	}
	if err := d.tasks.Remove(id); err != nil {
		return daemonCommandResult{err: fmt.Errorf("task remove: %w", err)}
	}
	return daemonCommandResult{message: fmt.Sprintf("task %d removed", pos)}
}

func (d *daemonCore) handleTaskList() daemonCommandResult {
	active := d.tasks.Active()
	if len(active) == 0 {
		return daemonCommandResult{message: "no active tasks"}
	}
	var lines []string
	for i, t := range active {
		lines = append(lines, fmt.Sprintf("  %d) %s", i+1, t.Description))
	}
	return daemonCommandResult{message: strings.Join(lines, "\n")}
}

func (d *daemonCore) handleTaskCompleted() daemonCommandResult {
	done := d.tasks.Completed()
	if len(done) == 0 {
		return daemonCommandResult{message: "no completed tasks"}
	}
	var lines []string
	for _, t := range done {
		lines = append(lines, fmt.Sprintf("  [done] %s (%s)", t.Description, t.CompletedAt.Format("15:04")))
	}
	return daemonCommandResult{message: strings.Join(lines, "\n")}
}

func (d *daemonCore) handleTaskClear() daemonCommandResult {
	if err := d.tasks.ClearCompleted(); err != nil {
		return daemonCommandResult{err: fmt.Errorf("clear completed: %w", err)}
	}
	return daemonCommandResult{message: "completed tasks cleared"}
}

func (d *daemonCore) focusedTasks() []task.Task {
	return append([]task.Task(nil), d.focused...)
}

func (d *daemonCore) isWorkSession() bool {
	return d.cycle.Status() == "pomodoro"
}

func (d *daemonCore) initTasks(path string) error {
	store, err := task.NewFileStore(path)
	if err != nil {
		return fmt.Errorf("init task store: %w", err)
	}
	d.tasks = store
	return nil
}
