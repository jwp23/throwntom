package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/signal"
	"syscall"
	"time"
)

type interactiveCallbacks struct {
	StatusSnapshot func() (string, bool)
	Execute        func(command string) (daemonControlResponse, error)
}

type interactiveLoopState struct {
	statusLine     string
	morningPending bool
	prompt         promptState
}

type loopAction int

const (
	loopContinue loopAction = iota
	loopExit
)

func runInteractiveLoop(ui *terminalUI, in *os.File, callbacks interactiveCallbacks) (err error) {
	if callbacks.StatusSnapshot == nil || callbacks.Execute == nil {
		return fmt.Errorf("interactive callbacks must provide status snapshot and execute handlers")
	}

	state, err := enableRawMode(in)
	if err != nil {
		return err
	}
	defer func() {
		restoreErr := restoreTerminal(in, state)
		if err == nil && restoreErr != nil {
			err = restoreErr
		}
	}()

	keyEvents := make(chan keyEvent, 32)
	readErr := make(chan error, 1)
	go readKeyEvents(in, keyEvents, readErr)

	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()

	resizeSignals := make(chan os.Signal, 1)
	resizeEvents := make(chan struct{}, 1)
	stopResize := make(chan struct{})
	signal.Notify(resizeSignals, syscall.SIGWINCH)
	defer signal.Stop(resizeSignals)
	go func() {
		defer close(resizeEvents)
		for {
			select {
			case <-stopResize:
				return
			case _, ok := <-resizeSignals:
				if !ok {
					return
				}
				select {
				case resizeEvents <- struct{}{}:
				default:
				}
			}
		}
	}()
	defer close(stopResize)

	if width, widthErr := terminalWidth(in); widthErr == nil {
		ui.SetWidth(width)
	}

	return runInteractiveEventLoop(ui, callbacks, keyEvents, ticker.C, resizeEvents, readErr)
}

func runInteractiveEventLoop(
	ui *terminalUI,
	callbacks interactiveCallbacks,
	keyEvents <-chan keyEvent,
	ticks <-chan time.Time,
	resizes <-chan struct{},
	readErr <-chan error,
) error {
	statusLine, morningPending := callbacks.StatusSnapshot()
	state := interactiveLoopState{
		statusLine:     statusLine,
		morningPending: morningPending,
		prompt:         promptState{},
	}
	ui.ShowFrameWithInput(state.statusLine, state.morningPending, state.prompt.input)

	for {
		select {
		case ev, ok := <-keyEvents:
			if !ok {
				keyEvents = nil
				continue
			}
			action, err := handleInteractiveKeyEvent(ui, callbacks, &state, ev)
			if err != nil {
				return err
			}
			if action == loopExit {
				return nil
			}
		case _, ok := <-ticks:
			if !ok {
				ticks = nil
				continue
			}
			handleInteractiveTick(ui, callbacks, &state)
		case _, ok := <-resizes:
			if !ok {
				resizes = nil
				continue
			}
			handleInteractiveResize(ui, &state)
		case err, ok := <-readErr:
			if !ok {
				readErr = nil
				continue
			}
			action, loopErr := handleInteractiveReadErr(err)
			if loopErr != nil {
				return loopErr
			}
			if action == loopExit {
				return nil
			}
		}
	}
}

func handleInteractiveKeyEvent(ui *terminalUI, callbacks interactiveCallbacks, state *interactiveLoopState, ev keyEvent) (loopAction, error) {
	if ev.kind == keyInterrupt {
		return loopExit, nil
	}

	nextPrompt, submitted, handled := applyKey(state.prompt, ev)
	if !handled {
		return loopContinue, nil
	}

	state.prompt = nextPrompt
	if submitted == "" {
		ui.ShowFrameWithInput(state.statusLine, state.morningPending, state.prompt.input)
		return loopContinue, nil
	}

	resp, err := callbacks.Execute(submitted)
	if err != nil {
		ui.Println(err.Error())
		state.statusLine, state.morningPending = callbacks.StatusSnapshot()
		ui.ShowFrameWithInput(state.statusLine, state.morningPending, state.prompt.input)
		return loopContinue, nil
	}

	state.statusLine, state.morningPending = resp.StatusLine, resp.MorningPending
	renderResponseMessage(ui, resp)
	ui.ShowFrameWithInput(state.statusLine, state.morningPending, state.prompt.input)
	if resp.Exit {
		return loopExit, nil
	}
	return loopContinue, nil
}

func handleInteractiveTick(ui *terminalUI, callbacks interactiveCallbacks, state *interactiveLoopState) {
	state.statusLine, state.morningPending = callbacks.StatusSnapshot()
	ui.ShowFrameWithInput(state.statusLine, state.morningPending, state.prompt.input)
}

func handleInteractiveResize(ui *terminalUI, state *interactiveLoopState) {
	if width, err := terminalWidth(os.Stdin); err == nil {
		ui.SetWidth(width)
	}
	ui.ShowFrameWithInput(state.statusLine, state.morningPending, state.prompt.input)
}

func handleInteractiveReadErr(err error) (loopAction, error) {
	if errors.Is(err, io.EOF) {
		return loopExit, nil
	}
	return loopContinue, fmt.Errorf("read input: %w", err)
}

func readKeyEvents(in *os.File, out chan<- keyEvent, errs chan<- error) {
	defer close(out)
	defer close(errs)

	buf := make([]byte, 1)
	for {
		n, err := in.Read(buf)
		if err != nil {
			if !errors.Is(err, io.EOF) {
				errs <- err
			}
			return
		}
		if n == 0 {
			continue
		}

		ev, ok := parseKeyEvent(buf[:n])
		if !ok {
			continue
		}
		out <- ev
	}
}
