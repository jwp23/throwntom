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
	case "focus":
		return d.handleTaskFocus(parts)
	case "unfocus":
		return d.handleTaskUnfocus(parts)
	case "up":
		return d.handleTaskUp(parts)
	case "down":
		return d.handleTaskDown(parts)
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
	for i, f := range d.focused {
		if f.ID == id {
			d.focused = append(d.focused[:i], d.focused[i+1:]...)
			break
		}
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

func (d *daemonCore) handleTaskFocus(parts []string) daemonCommandResult {
	if !d.isWorkSession() {
		return daemonCommandResult{err: fmt.Errorf("focus is only available during a work session")}
	}
	if len(parts) < 3 {
		return daemonCommandResult{err: fmt.Errorf("usage: task focus <n>")}
	}
	pos, err := strconv.Atoi(parts[2])
	if err != nil {
		return daemonCommandResult{err: fmt.Errorf("invalid task number: %s", parts[2])}
	}
	id, err := d.tasks.ActiveTaskID(pos)
	if err != nil {
		return daemonCommandResult{err: fmt.Errorf("task focus: %w", err)}
	}
	for _, f := range d.focused {
		if f.ID == id {
			return daemonCommandResult{err: fmt.Errorf("task %d is already focused", pos)}
		}
	}
	active := d.tasks.Active()
	for _, t := range active {
		if t.ID == id {
			d.focused = append(d.focused, t)
			return daemonCommandResult{message: fmt.Sprintf("focused on task %d: %s", pos, t.Description)}
		}
	}
	return daemonCommandResult{err: fmt.Errorf("task %d not found in active list", pos)}
}

func (d *daemonCore) handleTaskUnfocus(parts []string) daemonCommandResult {
	if !d.isWorkSession() {
		return daemonCommandResult{err: fmt.Errorf("unfocus is only available during a work session")}
	}
	if len(parts) < 3 {
		return daemonCommandResult{err: fmt.Errorf("usage: task unfocus <n>")}
	}
	pos, err := strconv.Atoi(parts[2])
	if err != nil {
		return daemonCommandResult{err: fmt.Errorf("invalid position: %s", parts[2])}
	}
	if pos < 1 || pos > len(d.focused) {
		return daemonCommandResult{err: fmt.Errorf("position %d out of range (1-%d)", pos, len(d.focused))}
	}
	d.focused = append(d.focused[:pos-1], d.focused[pos:]...)
	return daemonCommandResult{message: fmt.Sprintf("unfocused task at position %d", pos)}
}

func (d *daemonCore) handleTaskUp(parts []string) daemonCommandResult {
	if !d.isWorkSession() {
		return daemonCommandResult{err: fmt.Errorf("up is only available during a work session")}
	}
	if len(parts) < 3 {
		return daemonCommandResult{err: fmt.Errorf("usage: task up <n>")}
	}
	pos, err := strconv.Atoi(parts[2])
	if err != nil {
		return daemonCommandResult{err: fmt.Errorf("invalid position: %s", parts[2])}
	}
	if pos < 2 || pos > len(d.focused) {
		return daemonCommandResult{err: fmt.Errorf("position %d out of range for up (2-%d)", pos, len(d.focused))}
	}
	d.focused[pos-1], d.focused[pos-2] = d.focused[pos-2], d.focused[pos-1]
	return daemonCommandResult{message: fmt.Sprintf("moved task up to position %d", pos-1)}
}

func (d *daemonCore) handleTaskDown(parts []string) daemonCommandResult {
	if !d.isWorkSession() {
		return daemonCommandResult{err: fmt.Errorf("down is only available during a work session")}
	}
	if len(parts) < 3 {
		return daemonCommandResult{err: fmt.Errorf("usage: task down <n>")}
	}
	pos, err := strconv.Atoi(parts[2])
	if err != nil {
		return daemonCommandResult{err: fmt.Errorf("invalid position: %s", parts[2])}
	}
	if pos < 1 || pos >= len(d.focused) {
		return daemonCommandResult{err: fmt.Errorf("position %d out of range for down (1-%d)", pos, len(d.focused)-1)}
	}
	d.focused[pos-1], d.focused[pos] = d.focused[pos], d.focused[pos-1]
	return daemonCommandResult{message: fmt.Sprintf("moved task down to position %d", pos+1)}
}

func (d *daemonCore) enterFocusPrompt(action string) daemonCommandResult {
	d.pendingFocusPrompt = true
	d.pendingFocusToggled = make(map[int]bool)
	d.pendingFocusAction = action
	return daemonCommandResult{message: d.formatFocusPrompt()}
}

func (d *daemonCore) handleFocusPromptInput(input string) daemonCommandResult {
	if input == "" {
		return d.finalizeFocusPrompt()
	}
	if strings.HasPrefix(input, "a ") {
		desc := strings.TrimPrefix(input, "a ")
		t, err := d.tasks.Add(desc)
		if err != nil {
			return daemonCommandResult{err: fmt.Errorf("add task: %w", err)}
		}
		d.pendingFocusToggled[t.ID] = true
		return daemonCommandResult{message: d.formatFocusPrompt()}
	}
	pos, err := strconv.Atoi(input)
	if err != nil {
		return daemonCommandResult{err: fmt.Errorf("invalid input during task selection")}
	}
	active := d.tasks.Active()
	if pos < 1 || pos > len(active) {
		return daemonCommandResult{err: fmt.Errorf("position %d out of range (1-%d)", pos, len(active))}
	}
	id := active[pos-1].ID
	if d.pendingFocusToggled[id] {
		delete(d.pendingFocusToggled, id)
	} else {
		d.pendingFocusToggled[id] = true
	}
	return daemonCommandResult{message: d.formatFocusPrompt()}
}

func (d *daemonCore) finalizeFocusPrompt() daemonCommandResult {
	active := d.tasks.Active()
	var focused []task.Task
	for _, t := range active {
		if d.pendingFocusToggled[t.ID] {
			focused = append(focused, t)
		}
	}
	d.focused = focused
	d.pendingFocusPrompt = false
	d.pendingFocusToggled = nil
	action := d.pendingFocusAction
	d.pendingFocusAction = ""
	if action == "start" {
		d.cycle.Start()
	}
	return daemonCommandResult{message: "pomodoro started"}
}

func (d *daemonCore) formatFocusPrompt() string {
	active := d.tasks.Active()
	var lines []string
	lines = append(lines, "Select tasks for this pomodoro:")
	for i, tk := range active {
		marker := " "
		if d.pendingFocusToggled[tk.ID] {
			marker = "*"
		}
		lines = append(lines, fmt.Sprintf(" %s%d) %s", marker, i+1, tk.Description))
	}
	var selected []string
	for i, tk := range active {
		if d.pendingFocusToggled[tk.ID] {
			selected = append(selected, fmt.Sprintf("%d", i+1))
		}
	}
	if len(selected) > 0 {
		lines = append(lines, "", fmt.Sprintf("Focused: %s", strings.Join(selected, ", ")))
	}
	lines = append(lines, "", "(numbers to toggle, a <desc> to add, enter to start, esc to cancel)")
	return strings.Join(lines, "\n")
}

func (d *daemonCore) cancelFocusPrompt() daemonCommandResult {
	d.pendingFocusPrompt = false
	d.pendingFocusToggled = nil
	d.pendingFocusAction = ""
	return daemonCommandResult{message: "task selection cancelled"}
}

func (d *daemonCore) focusedTasks() []task.Task {
	return append([]task.Task(nil), d.focused...)
}

func (d *daemonCore) isFocusPromptPending() bool {
	return d.pendingFocusPrompt
}

func (d *daemonCore) formatFocusLines() []string {
	if len(d.focused) == 0 {
		return nil
	}
	lines := []string{"Focus:"}
	for i, tk := range d.focused {
		lines = append(lines, fmt.Sprintf("  %d. %s", i+1, tk.Description))
	}
	return lines
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
