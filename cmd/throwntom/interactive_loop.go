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
	prompt := promptState{}
	ui.ShowFrameWithInput(statusLine, morningPending, prompt.input)

	for {
		select {
		case ev, ok := <-keyEvents:
			if !ok {
				keyEvents = nil
				continue
			}
			nextPrompt, submitted, handled := applyKey(prompt, ev)
			if !handled {
				continue
			}
			prompt = nextPrompt
			if submitted == "" {
				ui.ShowFrameWithInput(statusLine, morningPending, prompt.input)
				continue
			}

			resp, err := callbacks.Execute(submitted)
			if err != nil {
				ui.Println(err.Error())
				statusLine, morningPending = callbacks.StatusSnapshot()
				ui.ShowFrameWithInput(statusLine, morningPending, prompt.input)
				continue
			}

			statusLine, morningPending = resp.StatusLine, resp.MorningPending
			renderResponseMessage(ui, resp)
			ui.ShowFrameWithInput(statusLine, morningPending, prompt.input)
			if resp.Exit {
				return nil
			}
		case _, ok := <-ticks:
			if !ok {
				ticks = nil
				continue
			}
			statusLine, morningPending = callbacks.StatusSnapshot()
			ui.ShowFrameWithInput(statusLine, morningPending, prompt.input)
		case _, ok := <-resizes:
			if !ok {
				resizes = nil
				continue
			}
			ui.ShowFrameWithInput(statusLine, morningPending, prompt.input)
		case err, ok := <-readErr:
			if !ok {
				readErr = nil
				continue
			}
			if errors.Is(err, io.EOF) {
				return nil
			}
			return fmt.Errorf("read input: %w", err)
		}
	}
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
