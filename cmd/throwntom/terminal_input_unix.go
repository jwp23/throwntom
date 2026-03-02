//go:build darwin || linux

package main

import (
	"fmt"
	"os"
	"syscall"
	"unsafe"
)

type terminalState struct {
	original syscall.Termios
}

func parseKeyEvent(buf []byte) (keyEvent, bool) {
	if len(buf) == 0 {
		return keyEvent{}, false
	}

	switch buf[0] {
	case '\r', '\n':
		return keyEvent{kind: keyEnter}, true
	case 0x08, 0x7f:
		return keyEvent{kind: keyBackspace}, true
	default:
		if buf[0] >= 32 && buf[0] <= 126 {
			return keyEvent{kind: keyPrintable, r: rune(buf[0])}, true
		}
		return keyEvent{}, false
	}
}

func enableRawMode(file *os.File) (*terminalState, error) {
	fd := file.Fd()
	original, err := getTermios(fd)
	if err != nil {
		return nil, fmt.Errorf("read terminal state: %w", err)
	}

	raw := original
	raw.Iflag &^= syscall.IGNBRK | syscall.BRKINT | syscall.PARMRK | syscall.ISTRIP | syscall.INLCR | syscall.IGNCR | syscall.ICRNL | syscall.IXON
	raw.Oflag &^= syscall.OPOST
	raw.Lflag &^= syscall.ECHO | syscall.ECHONL | syscall.ICANON | syscall.ISIG | syscall.IEXTEN
	raw.Cflag &^= syscall.CSIZE | syscall.PARENB
	raw.Cflag |= syscall.CS8
	raw.Cc[syscall.VMIN] = 1
	raw.Cc[syscall.VTIME] = 0

	if err := setTermios(fd, &raw); err != nil {
		return nil, fmt.Errorf("set raw terminal mode: %w", err)
	}
	return &terminalState{original: original}, nil
}

func restoreTerminal(file *os.File, state *terminalState) error {
	if state == nil {
		return nil
	}
	if err := setTermios(file.Fd(), &state.original); err != nil {
		return fmt.Errorf("restore terminal mode: %w", err)
	}
	return nil
}

func getTermios(fd uintptr) (syscall.Termios, error) {
	var termios syscall.Termios
	_, _, errno := syscall.Syscall6(
		syscall.SYS_IOCTL,
		fd,
		uintptr(ioctlReadTermios),
		uintptr(unsafe.Pointer(&termios)),
		0,
		0,
		0,
	)
	if errno != 0 {
		return syscall.Termios{}, errno
	}
	return termios, nil
}

func setTermios(fd uintptr, termios *syscall.Termios) error {
	_, _, errno := syscall.Syscall6(
		syscall.SYS_IOCTL,
		fd,
		uintptr(ioctlWriteTermios),
		uintptr(unsafe.Pointer(termios)),
		0,
		0,
		0,
	)
	if errno != 0 {
		return errno
	}
	return nil
}
