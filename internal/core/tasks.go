package core

import (
	"errors"
	"fmt"
	"strconv"
	"strings"

	"github.com/jwp23/throwntom/v3/internal/engine"
	"github.com/jwp23/throwntom/v3/internal/task"
)

type TaskList struct {
	Active    []task.Task `json:"active"`
	Completed []task.Task `json:"completed"`
}

const (
	fmtInvalidTaskNumber = "invalid task number: %s"
	fmtInvalidPosition   = "invalid position: %s"
)

func (c *Core) requireWorkSession(name string) (commandResult, bool) {
	if !c.isWorkSession() {
		return commandResult{err: fmt.Errorf("%s is %w", name, errNotWorkSession)}, false
	}
	return commandResult{}, true
}

func parseTaskPosition(parts []string, usage, errFmt string) (int, commandResult, bool) {
	if len(parts) < 3 {
		return 0, commandResult{err: errors.New(usage)}, false
	}
	pos, err := strconv.Atoi(parts[2])
	if err != nil {
		return 0, commandResult{err: fmt.Errorf(errFmt, parts[2])}, false
	}
	return pos, commandResult{}, true
}

func (c *Core) handleTask(parts []string) commandResult {
	if c.tasks == nil {
		return commandResult{err: fmt.Errorf("task store not initialized")}
	}
	if len(parts) < 2 {
		return commandResult{err: fmt.Errorf("usage: task <subcommand>")}
	}
	switch parts[1] {
	case "add":
		return c.handleTaskAdd(parts)
	case "done":
		return c.handleTaskDone(parts)
	case "remove":
		return c.handleTaskRemove(parts)
	case "list":
		return c.handleTaskList()
	case "completed":
		return c.handleTaskCompleted()
	case "clear":
		return c.handleTaskClear()
	case "focus":
		return c.handleTaskFocus(parts)
	case "unfocus":
		return c.handleTaskUnfocus(parts)
	case "up":
		return c.handleTaskUp(parts)
	case "down":
		return c.handleTaskDown(parts)
	default:
		return commandResult{err: fmt.Errorf("unknown task subcommand: %s", parts[1])}
	}
}

func (c *Core) handleTaskAdd(parts []string) commandResult {
	if len(parts) < 3 {
		return commandResult{err: fmt.Errorf("usage: task add <description>")}
	}
	desc := strings.Join(parts[2:], " ")
	t, err := c.tasks.Add(desc)
	if err != nil {
		return commandResult{err: fmt.Errorf("add task: %w", err)}
	}
	return commandResult{message: fmt.Sprintf("added task %d: %s", t.ID, t.Description)}
}

func (c *Core) handleTaskDone(parts []string) commandResult {
	pos, res, ok := parseTaskPosition(parts, "usage: task done <n>", fmtInvalidTaskNumber)
	if !ok {
		return res
	}
	id, err := c.tasks.ActiveTaskID(pos)
	if err != nil {
		return commandResult{err: fmt.Errorf("task done: %w", err)}
	}
	if err := c.tasks.Complete(id); err != nil {
		return commandResult{err: fmt.Errorf("task done: %w", err)}
	}
	for i, f := range c.focused {
		if f.ID == id {
			c.focused = append(c.focused[:i], c.focused[i+1:]...)
			break
		}
	}
	return commandResult{message: fmt.Sprintf("task %d completed", pos)}
}

func (c *Core) handleTaskRemove(parts []string) commandResult {
	pos, res, ok := parseTaskPosition(parts, "usage: task remove <n>", fmtInvalidTaskNumber)
	if !ok {
		return res
	}
	id, err := c.tasks.ActiveTaskID(pos)
	if err != nil {
		return commandResult{err: fmt.Errorf("task remove: %w", err)}
	}
	if err := c.tasks.Remove(id); err != nil {
		return commandResult{err: fmt.Errorf("task remove: %w", err)}
	}
	for i, f := range c.focused {
		if f.ID == id {
			c.focused = append(c.focused[:i], c.focused[i+1:]...)
			break
		}
	}
	return commandResult{message: fmt.Sprintf("task %d removed", pos)}
}

func (c *Core) handleTaskList() commandResult {
	active := c.tasks.Active()
	if len(active) == 0 {
		return commandResult{message: "no active tasks"}
	}
	var lines []string
	for i, t := range active {
		lines = append(lines, fmt.Sprintf("  %d) %s", i+1, t.Description))
	}
	return commandResult{message: strings.Join(lines, "\n")}
}

func (c *Core) handleTaskCompleted() commandResult {
	done := c.tasks.Completed()
	if len(done) == 0 {
		return commandResult{message: "no completed tasks"}
	}
	var lines []string
	for _, t := range done {
		lines = append(lines, fmt.Sprintf("  [done] %s (%s)", t.Description, t.CompletedAt.Format("15:04")))
	}
	return commandResult{message: strings.Join(lines, "\n")}
}

func (c *Core) handleTaskClear() commandResult {
	if err := c.tasks.ClearCompleted(); err != nil {
		return commandResult{err: fmt.Errorf("clear completed: %w", err)}
	}
	return commandResult{message: "completed tasks cleared"}
}

func (c *Core) handleTaskFocus(parts []string) commandResult {
	if res, ok := c.requireWorkSession("focus"); !ok {
		return res
	}
	pos, res, ok := parseTaskPosition(parts, "usage: task focus <n>", fmtInvalidTaskNumber)
	if !ok {
		return res
	}
	id, err := c.tasks.ActiveTaskID(pos)
	if err != nil {
		return commandResult{err: fmt.Errorf("task focus: %w", err)}
	}
	for _, f := range c.focused {
		if f.ID == id {
			return commandResult{err: fmt.Errorf("task %d %w", pos, errAlreadyFocused)}
		}
	}
	active := c.tasks.Active()
	for _, t := range active {
		if t.ID == id {
			c.focused = append(c.focused, t)
			return commandResult{message: fmt.Sprintf("focused on task %d: %s", pos, t.Description)}
		}
	}
	return commandResult{err: fmt.Errorf("task %d not found in active list", pos)}
}

func (c *Core) handleTaskUnfocus(parts []string) commandResult {
	if res, ok := c.requireWorkSession("unfocus"); !ok {
		return res
	}
	pos, res, ok := parseTaskPosition(parts, "usage: task unfocus <n>", fmtInvalidPosition)
	if !ok {
		return res
	}
	if pos < 1 || pos > len(c.focused) {
		return commandResult{err: fmt.Errorf("position %d out of range (1-%d)", pos, len(c.focused))}
	}
	c.focused = append(c.focused[:pos-1], c.focused[pos:]...)
	return commandResult{message: fmt.Sprintf("unfocused task at position %d", pos)}
}

func (c *Core) handleTaskUp(parts []string) commandResult {
	if res, ok := c.requireWorkSession("up"); !ok {
		return res
	}
	pos, res, ok := parseTaskPosition(parts, "usage: task up <n>", fmtInvalidPosition)
	if !ok {
		return res
	}
	if pos < 2 || pos > len(c.focused) {
		return commandResult{err: fmt.Errorf("position %d out of range for up (2-%d)", pos, len(c.focused))}
	}
	c.focused[pos-1], c.focused[pos-2] = c.focused[pos-2], c.focused[pos-1]
	return commandResult{message: fmt.Sprintf("moved task up to position %d", pos-1)}
}

func (c *Core) handleTaskDown(parts []string) commandResult {
	if res, ok := c.requireWorkSession("down"); !ok {
		return res
	}
	pos, res, ok := parseTaskPosition(parts, "usage: task down <n>", fmtInvalidPosition)
	if !ok {
		return res
	}
	if pos < 1 || pos >= len(c.focused) {
		return commandResult{err: fmt.Errorf("position %d out of range for down (1-%d)", pos, len(c.focused)-1)}
	}
	c.focused[pos-1], c.focused[pos] = c.focused[pos], c.focused[pos-1]
	return commandResult{message: fmt.Sprintf("moved task down to position %d", pos+1)}
}

func (c *Core) enterFocusPrompt(action string) commandResult {
	c.pendingFocusPrompt = true
	c.pendingFocusToggled = make(map[int]bool)
	c.pendingFocusAction = action
	return commandResult{message: c.focusPromptLocked()}
}

func (c *Core) handleFocusPromptInput(input string) commandResult {
	if input == "" {
		return c.finalizeFocusPrompt()
	}
	if strings.HasPrefix(input, "a ") {
		desc := strings.TrimPrefix(input, "a ")
		t, err := c.tasks.Add(desc)
		if err != nil {
			return commandResult{err: fmt.Errorf("add task: %w", err)}
		}
		c.pendingFocusToggled[t.ID] = true
		return commandResult{message: c.focusPromptLocked()}
	}
	pos, err := strconv.Atoi(input)
	if err != nil {
		return commandResult{err: fmt.Errorf("invalid input during task selection")}
	}
	active := c.tasks.Active()
	if pos < 1 || pos > len(active) {
		return commandResult{err: fmt.Errorf("position %d out of range (1-%d)", pos, len(active))}
	}
	id := active[pos-1].ID
	if c.pendingFocusToggled[id] {
		delete(c.pendingFocusToggled, id)
	} else {
		c.pendingFocusToggled[id] = true
	}
	return commandResult{message: c.focusPromptLocked()}
}

func (c *Core) finalizeFocusPrompt() commandResult {
	active := c.tasks.Active()
	var focused []task.Task
	for _, t := range active {
		if c.pendingFocusToggled[t.ID] {
			focused = append(focused, t)
		}
	}
	c.focused = focused
	c.pendingFocusPrompt = false
	c.pendingFocusToggled = nil
	action := c.pendingFocusAction
	c.pendingFocusAction = ""
	if action == "start" {
		c.cycle.Start()
		c.logEvent("pomodoro_started", nil)
	}
	return commandResult{message: "Pomodoro started -- let's go!"}
}

func (c *Core) FocusPrompt() string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.focusPromptLocked()
}

func (c *Core) focusPromptLocked() string {
	active := c.tasks.Active()
	var lines []string
	lines = append(lines, "Select tasks for this pomodoro:")
	for i, tk := range active {
		marker := " "
		if c.pendingFocusToggled[tk.ID] {
			marker = "*"
		}
		lines = append(lines, fmt.Sprintf(" %s%d) %s", marker, i+1, tk.Description))
	}
	var selected []string
	for i, tk := range active {
		if c.pendingFocusToggled[tk.ID] {
			selected = append(selected, fmt.Sprintf("%d", i+1))
		}
	}
	if len(selected) > 0 {
		lines = append(lines, "", fmt.Sprintf("Focused: %s", strings.Join(selected, ", ")))
	}
	lines = append(lines, "", "(numbers to toggle, a <desc> to add, enter to start, esc to cancel)")
	return strings.Join(lines, "\n")
}

func (c *Core) cancelFocusPrompt() commandResult {
	c.pendingFocusPrompt = false
	c.pendingFocusToggled = nil
	c.pendingFocusAction = ""
	return commandResult{message: "task selection cancelled"}
}

func (c *Core) Focused() []task.Task {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.focusedLocked()
}

func (c *Core) focusedLocked() []task.Task {
	return append([]task.Task(nil), c.focused...)
}

func (c *Core) FocusPromptPending() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.pendingFocusPrompt
}

func (c *Core) isWorkSession() bool {
	return c.cycle.State() == engine.Work
}

func (c *Core) initTasks(path string) error {
	store, err := task.NewFileStore(path)
	if err != nil {
		return fmt.Errorf("init task store: %w", err)
	}
	c.tasks = store
	return nil
}

// Tasks returns a copy of the active and completed task lists.
func (c *Core) Tasks() TaskList {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.tasks == nil {
		return TaskList{}
	}
	return TaskList{Active: c.tasks.Active(), Completed: c.tasks.Completed()}
}

// AddTask creates a new task with the given description and publishes the change.
// It returns an error if the task store is nil or the description is empty.
func (c *Core) AddTask(description string) (task.Task, error) {
	c.mu.Lock()
	if c.tasks == nil {
		c.mu.Unlock()
		return task.Task{}, fmt.Errorf("task store not initialized")
	}
	if strings.TrimSpace(description) == "" {
		c.mu.Unlock()
		return task.Task{}, fmt.Errorf("description is required")
	}
	t, err := c.tasks.Add(strings.TrimSpace(description))
	c.mu.Unlock()
	if err != nil {
		return task.Task{}, err
	}
	c.publish()
	return t, nil
}
