// Package atomicfile provides a single helper for atomically writing a file
// to disk with an explicit permission mode.
package atomicfile

import (
	"fmt"
	"os"
	"path/filepath"
)

// createFn, chmodFn, writeFn, closeFn and renameFn default to the real os
// operations. Tests override them to exercise error branches (chmod, write,
// close and rename failures) that cannot be reliably triggered through the
// real filesystem.
var (
	createFn = os.CreateTemp
	chmodFn  = func(f *os.File, mode os.FileMode) error { return f.Chmod(mode) }
	writeFn  = func(f *os.File, data []byte) (int, error) { return f.Write(data) }
	closeFn  = func(f *os.File) error { return f.Close() }
	renameFn = os.Rename
)

// Write atomically replaces the file at path with data, using mode for the
// file's permissions. It creates a temp file in path's directory, chmods it
// explicitly, writes data, closes it, and renames it over path. Readers of
// path either see the previous contents or the new ones, never a partial
// write. If any step fails, the temp file is removed and the existing
// target, if any, is left untouched.
func Write(path string, data []byte, mode os.FileMode) error {
	tmp, err := createFn(filepath.Dir(path), filepath.Base(path)+".tmp*")
	if err != nil {
		return fmt.Errorf("create temp file: %w", err)
	}
	tmpName := tmp.Name()
	defer func() { _ = os.Remove(tmpName) }()

	if err := chmodFn(tmp, mode); err != nil {
		_ = closeFn(tmp)
		return fmt.Errorf("chmod temp file: %w", err)
	}
	if _, err := writeFn(tmp, data); err != nil {
		_ = closeFn(tmp)
		return fmt.Errorf("write temp file: %w", err)
	}
	if err := closeFn(tmp); err != nil {
		return fmt.Errorf("close temp file: %w", err)
	}
	if err := renameFn(tmpName, path); err != nil {
		return fmt.Errorf("rename temp file: %w", err)
	}
	return nil
}
