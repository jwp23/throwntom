package atomicfile

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestWriteCreatesFileWithContentAndMode(t *testing.T) {
	path := filepath.Join(t.TempDir(), "out.json")

	if err := Write(path, []byte("hello"), 0o640); err != nil {
		t.Fatalf("Write: %v", err)
	}

	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("Stat: %v", err)
	}
	if info.Mode().Perm() != 0o640 {
		t.Errorf("mode: got %o, want %o", info.Mode().Perm(), 0o640)
	}
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	if string(got) != "hello" {
		t.Errorf("content: got %q, want %q", got, "hello")
	}
}

func TestWriteOverwritesExistingFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "out.json")
	if err := os.WriteFile(path, []byte("old"), 0o600); err != nil {
		t.Fatal(err)
	}

	if err := Write(path, []byte("new"), 0o600); err != nil {
		t.Fatalf("Write: %v", err)
	}

	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	if string(got) != "new" {
		t.Errorf("content: got %q, want %q", got, "new")
	}
}

func TestWriteMissingDirReturnsError(t *testing.T) {
	path := filepath.Join(t.TempDir(), "missing", "out.json")

	if err := Write(path, []byte("x"), 0o600); err == nil {
		t.Fatal("expected error for missing directory")
	}
}

func noTempFilesLeftBehind(t *testing.T, dir string) {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("ReadDir: %v", err)
	}
	for _, e := range entries {
		if filepath.Ext(e.Name()) != ".json" || filepath.Base(e.Name()) != "out.json" {
			t.Errorf("leftover temp file: %s", e.Name())
		}
	}
}

func TestWriteChmodFailureCleansUpTempAndPreservesTarget(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "out.json")
	if err := os.WriteFile(path, []byte("original"), 0o600); err != nil {
		t.Fatal(err)
	}

	orig := chmodFn
	defer func() { chmodFn = orig }()
	wantErr := errors.New("chmod boom")
	chmodFn = func(*os.File, os.FileMode) error { return wantErr }

	err := Write(path, []byte("new"), 0o600)
	if !errors.Is(err, wantErr) {
		t.Fatalf("expected wrapped %v, got %v", wantErr, err)
	}

	got, readErr := os.ReadFile(path)
	if readErr != nil {
		t.Fatalf("ReadFile: %v", readErr)
	}
	if string(got) != "original" {
		t.Errorf("target was modified: got %q, want %q", got, "original")
	}
	noTempFilesLeftBehind(t, dir)
}

func TestWriteWriteFailureCleansUpTempAndPreservesTarget(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "out.json")
	if err := os.WriteFile(path, []byte("original"), 0o600); err != nil {
		t.Fatal(err)
	}

	orig := writeFn
	defer func() { writeFn = orig }()
	wantErr := errors.New("write boom")
	writeFn = func(*os.File, []byte) (int, error) { return 0, wantErr }

	err := Write(path, []byte("new"), 0o600)
	if !errors.Is(err, wantErr) {
		t.Fatalf("expected wrapped %v, got %v", wantErr, err)
	}

	got, readErr := os.ReadFile(path)
	if readErr != nil {
		t.Fatalf("ReadFile: %v", readErr)
	}
	if string(got) != "original" {
		t.Errorf("target was modified: got %q, want %q", got, "original")
	}
	noTempFilesLeftBehind(t, dir)
}

func TestWriteCloseFailureCleansUpTempAndPreservesTarget(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "out.json")
	if err := os.WriteFile(path, []byte("original"), 0o600); err != nil {
		t.Fatal(err)
	}

	orig := closeFn
	defer func() { closeFn = orig }()
	wantErr := errors.New("close boom")
	closeFn = func(*os.File) error { return wantErr }

	err := Write(path, []byte("new"), 0o600)
	if !errors.Is(err, wantErr) {
		t.Fatalf("expected wrapped %v, got %v", wantErr, err)
	}

	got, readErr := os.ReadFile(path)
	if readErr != nil {
		t.Fatalf("ReadFile: %v", readErr)
	}
	if string(got) != "original" {
		t.Errorf("target was modified: got %q, want %q", got, "original")
	}
	noTempFilesLeftBehind(t, dir)
}

func TestWriteRenameFailureCleansUpTempAndPreservesTarget(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "out.json")
	if err := os.WriteFile(path, []byte("original"), 0o600); err != nil {
		t.Fatal(err)
	}

	orig := renameFn
	defer func() { renameFn = orig }()
	wantErr := errors.New("rename boom")
	renameFn = func(string, string) error { return wantErr }

	err := Write(path, []byte("new"), 0o600)
	if !errors.Is(err, wantErr) {
		t.Fatalf("expected wrapped %v, got %v", wantErr, err)
	}

	got, readErr := os.ReadFile(path)
	if readErr != nil {
		t.Fatalf("ReadFile: %v", readErr)
	}
	if string(got) != "original" {
		t.Errorf("target was modified: got %q, want %q", got, "original")
	}
	noTempFilesLeftBehind(t, dir)
}

func TestWriteCreateFailureReturnsError(t *testing.T) {
	orig := createFn
	defer func() { createFn = orig }()
	wantErr := errors.New("create boom")
	createFn = func(string, string) (*os.File, error) { return nil, wantErr }

	err := Write(filepath.Join(t.TempDir(), "out.json"), []byte("x"), 0o600)
	if !errors.Is(err, wantErr) {
		t.Fatalf("expected wrapped %v, got %v", wantErr, err)
	}
}

func TestWriteExclusiveCreatesFileWithContentAndMode(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "out.json")

	if err := WriteExclusive(path, []byte("hello"), 0o640); err != nil {
		t.Fatalf("WriteExclusive: %v", err)
	}

	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("Stat: %v", err)
	}
	if info.Mode().Perm() != 0o640 {
		t.Errorf("mode: got %o, want %o", info.Mode().Perm(), 0o640)
	}
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	if string(got) != "hello" {
		t.Errorf("content: got %q, want %q", got, "hello")
	}
	noTempFilesLeftBehind(t, dir)
}

// The whole point of WriteExclusive: a target that exists is left alone, not
// replaced, and reported as success rather than an error a caller has to
// special-case.
func TestWriteExclusiveLeavesAnExistingTargetAlone(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "out.json")
	if err := os.WriteFile(path, []byte("original"), 0o600); err != nil {
		t.Fatal(err)
	}

	if err := WriteExclusive(path, []byte("new"), 0o600); err != nil {
		t.Fatalf("WriteExclusive: %v", err)
	}

	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	if string(got) != "original" {
		t.Errorf("target was replaced: got %q, want %q", got, "original")
	}
	noTempFilesLeftBehind(t, dir)
}

// Simulates the race WriteExclusive exists to close: something else creates
// the target in the window between the staged write and the link.
func TestWriteExclusiveToleratesAConcurrentCreation(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "out.json")

	orig := linkFn
	defer func() { linkFn = orig }()
	linkFn = func(oldname, newname string) error {
		if err := os.WriteFile(newname, []byte("raced in first"), 0o600); err != nil {
			t.Fatal(err)
		}
		return os.Link(oldname, newname)
	}

	if err := WriteExclusive(path, []byte("new"), 0o600); err != nil {
		t.Fatalf("WriteExclusive: %v", err)
	}

	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	if string(got) != "raced in first" {
		t.Errorf("winner was overwritten: got %q, want %q", got, "raced in first")
	}
	noTempFilesLeftBehind(t, dir)
}

func TestWriteExclusiveLinkFailureCleansUpTempAndPreservesTarget(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "out.json")

	orig := linkFn
	defer func() { linkFn = orig }()
	wantErr := errors.New("link boom")
	linkFn = func(string, string) error { return wantErr }

	err := WriteExclusive(path, []byte("new"), 0o600)
	if !errors.Is(err, wantErr) {
		t.Fatalf("expected wrapped %v, got %v", wantErr, err)
	}
	if _, statErr := os.Stat(path); !os.IsNotExist(statErr) {
		t.Fatalf("target should not exist, stat err = %v", statErr)
	}
	noTempFilesLeftBehind(t, dir)
}
