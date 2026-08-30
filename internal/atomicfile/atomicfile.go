// Package atomicfile provides a single helper for atomically writing a file
// to disk with an explicit permission mode.
package atomicfile

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
)

// createFn, chmodFn, writeFn, closeFn, renameFn and linkFn default to the
// real os operations. Tests override them to exercise error branches
// (chmod, write, close, rename and link failures) that cannot be reliably
// triggered through the real filesystem.
var (
	createFn = os.CreateTemp
	chmodFn  = func(f *os.File, mode os.FileMode) error { return f.Chmod(mode) }
	writeFn  = func(f *os.File, data []byte) (int, error) { return f.Write(data) }
	closeFn  = func(f *os.File) error { return f.Close() }
	renameFn = os.Rename
	linkFn   = os.Link
)

// stage creates a temp file in path's directory, chmods it explicitly,
// writes data and closes it, ready for an atomic rename or link over path.
// The temp file's name is always returned so the caller can remove it, even
// on error.
func stage(path string, data []byte, mode os.FileMode) (tmpName string, err error) {
	tmp, err := createFn(filepath.Dir(path), filepath.Base(path)+".tmp*")
	if err != nil {
		return "", fmt.Errorf("create temp file: %w", err)
	}
	tmpName = tmp.Name()

	if err := chmodFn(tmp, mode); err != nil {
		_ = closeFn(tmp)
		return tmpName, fmt.Errorf("chmod temp file: %w", err)
	}
	if _, err := writeFn(tmp, data); err != nil {
		_ = closeFn(tmp)
		return tmpName, fmt.Errorf("write temp file: %w", err)
	}
	if err := closeFn(tmp); err != nil {
		return tmpName, fmt.Errorf("close temp file: %w", err)
	}
	return tmpName, nil
}

// Write atomically replaces the file at path with data, using mode for the
// file's permissions. It creates a temp file in path's directory, chmods it
// explicitly, writes data, closes it, and renames it over path. Readers of
// path either see the previous contents or the new ones, never a partial
// write. If any step fails, the temp file is removed and the existing
// target, if any, is left untouched.
func Write(path string, data []byte, mode os.FileMode) error {
	tmpName, err := stage(path, data, mode)
	defer func() { _ = os.Remove(tmpName) }()
	if err != nil {
		return err
	}
	if err := renameFn(tmpName, path); err != nil {
		return fmt.Errorf("rename temp file: %w", err)
	}
	return nil
}

// WriteExclusive writes data to path only when nothing is there yet, using
// mode for the file's permissions. Unlike Write, it never replaces an
// existing target: it links the staged temp file into place, which fails
// rather than clobbering if path is created by another process in the
// window between a caller's own existence check and this call. A path that
// already exists is treated as success, matching a caller who only wanted
// the file to end up present.
func WriteExclusive(path string, data []byte, mode os.FileMode) error {
	tmpName, err := stage(path, data, mode)
	defer func() { _ = os.Remove(tmpName) }()
	if err != nil {
		return err
	}
	if err := linkFn(tmpName, path); err != nil {
		if errors.Is(err, fs.ErrExist) {
			return nil
		}
		return fmt.Errorf("link temp file: %w", err)
	}
	return nil
}
