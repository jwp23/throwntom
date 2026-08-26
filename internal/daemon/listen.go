package daemon

import (
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"syscall"

	"github.com/jwp23/throwntom/v3/internal/core"
)

var ErrAlreadyRunning = errors.New("throwntomd is already running")

type lockedListener struct {
	net.Listener
	lock *os.File
	sock string
}

func (l *lockedListener) Close() error {
	err := l.Listener.Close()
	_ = os.Remove(l.sock)
	_ = syscall.Flock(int(l.lock.Fd()), syscall.LOCK_UN)
	_ = l.lock.Close()
	return err
}

// Listen acquires the single-instance lock, replaces a stale socket file and
// listens on paths.Socket. Closing the listener releases both.
func Listen(paths core.Paths) (net.Listener, error) {
	if err := os.MkdirAll(filepath.Dir(paths.Socket), 0o755); err != nil {
		return nil, fmt.Errorf("create socket directory: %w", err)
	}
	lock, err := os.OpenFile(paths.Lock, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, fmt.Errorf("open lock file: %w", err)
	}
	if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		_ = lock.Close()
		if errors.Is(err, syscall.EWOULDBLOCK) {
			return nil, ErrAlreadyRunning
		}
		return nil, fmt.Errorf("lock %s: %w", paths.Lock, err)
	}
	if err := os.Remove(paths.Socket); err != nil && !os.IsNotExist(err) {
		_ = lock.Close()
		return nil, fmt.Errorf("remove stale socket: %w", err)
	}
	ln, err := net.Listen("unix", paths.Socket)
	if err != nil {
		_ = lock.Close()
		return nil, fmt.Errorf("listen on %s: %w", paths.Socket, err)
	}
	if err := os.Chmod(paths.Socket, 0o600); err != nil {
		_ = ln.Close()
		_ = lock.Close()
		return nil, fmt.Errorf("restrict socket permissions: %w", err)
	}
	return &lockedListener{Listener: ln, lock: lock, sock: paths.Socket}, nil
}
