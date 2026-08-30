package main

import (
	"bytes"
	"errors"
	"io/fs"
	"os"
	"strings"
	"testing"
	"time"
)

// dump mirrors the shape of `lsregister -dump`: records separated by dashed
// rules, each with a `path:` line carrying a trailing handle in parentheses and
// an `identifier:` line naming the bundle id.
const dump = `--------------------------------------------------------------------------------
bundle id:                  Throwntom (0x35a)
path:                       /gone/worktree/macos/.build/Throwntom.app (0x1830)
name:                       Throwntom
identifier:                 com.jwp23.throwntom
codeInfoID:                 com.jwp23.throwntom
activityTypes:              NOTIFICATION#:com.jwp23.throwntom
--------------------------------------------------------------------------------
bundle id:                  WallpaperAgent (0x35c)
path:                       /gone/System/WallpaperAgent.app (0x10f0)
name:                       WallpaperAgent
identifier:                 com.apple.wallpaper.agent
--------------------------------------------------------------------------------
bundle id:                  Throwntom (0x35e)
path:                       /live/checkout/macos/.build/Throwntom.app (0x18bc)
name:                       Throwntom
identifier:                 com.jwp23.throwntom
infoDictionary:             3 values (25320 (0x62e8))
                            {
                                CFBundleIdentifier = "com.jwp23.throwntom";
                                CFBundleIconFile = Throwntom;
                            }
--------------------------------------------------------------------------------
bundle id:                  Stranger (0x35f)
path:                       /gone/Some Other App (0x1).app (0x1a00)
name:                       Stranger
identifier:                 com.example.stranger
                                CFBundleIdentifier = "com.jwp23.throwntom";
--------------------------------------------------------------------------------
bundle id:                  Impostor (0x360)
path:                       /gone/Impostor.app (0x1900)
name:                       Impostor
identifier:                 com.jwp23.throwntom.helper
codeInfoID:                 com.jwp23.throwntom
`

// statFunc answers for the fixture paths above: only /live/... exists.
func fixtureStat(path string) (fs.FileInfo, error) {
	if strings.HasPrefix(path, "/live/") {
		return fakeInfo{}, nil
	}
	return nil, fs.ErrNotExist
}

type fakeInfo struct{}

func (fakeInfo) Name() string       { return "Throwntom.app" }
func (fakeInfo) Size() int64        { return 0 }
func (fakeInfo) Mode() fs.FileMode  { return fs.ModeDir }
func (fakeInfo) ModTime() time.Time { return time.Time{} }
func (fakeInfo) IsDir() bool        { return true }
func (fakeInfo) Sys() any           { return nil }

func TestRegisteredPathsMatchesOnlyTheAppBundleID(t *testing.T) {
	got := registeredPaths(dump)
	want := []string{
		"/gone/worktree/macos/.build/Throwntom.app",
		"/live/checkout/macos/.build/Throwntom.app",
	}
	if len(got) != len(want) {
		t.Fatalf("got %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("path %d = %q, want %q", i, got[i], want[i])
		}
	}
}

// Real dumps carry paths with spaces, and the trailing store handle must come
// off without taking part of the path with it.
func TestRegisteredPathsKeepsSpacesAndDropsTheHandle(t *testing.T) {
	const spaced = `--------------------------------------------------------------------------------
bundle id:                  Throwntom (0x35a)
path:                       /Users/me/My Builds/Throwntom (0x1) copy.app (0x1830)
identifier:                 com.jwp23.throwntom
`
	got := registeredPaths(spaced)
	want := "/Users/me/My Builds/Throwntom (0x1) copy.app"
	if len(got) != 1 || got[0] != want {
		t.Fatalf("got %q, want [%q]", got, want)
	}
}

// An indented CFBundleIdentifier inside a foreign record's infoDictionary must
// never bring that record's path into range.
func TestRegisteredPathsIgnoresIndentedBundleIDFields(t *testing.T) {
	for _, path := range registeredPaths(dump) {
		if strings.Contains(path, "Some Other App") {
			t.Fatalf("selected a foreign path via an indented field: %q", path)
		}
	}
}

func TestRegisteredPathsIgnoresOtherBundleIDs(t *testing.T) {
	for _, path := range registeredPaths(dump) {
		if strings.Contains(path, "WallpaperAgent") || strings.Contains(path, "Impostor") {
			t.Fatalf("selected a foreign bundle's path: %q", path)
		}
	}
}

func TestStalePathsKeepsPathsThatStillExist(t *testing.T) {
	stale := stalePaths(registeredPaths(dump), fixtureStat)
	for _, path := range stale {
		if strings.HasPrefix(path, "/live/") {
			t.Fatalf("live path selected as stale: %q", path)
		}
	}
	if len(stale) != 1 || stale[0] != "/gone/worktree/macos/.build/Throwntom.app" {
		t.Fatalf("stale = %v, want the single gone worktree path", stale)
	}
}

// A stat error that is not "does not exist" (a permission failure on a mounted
// volume, say) must never be read as absence.
func TestStalePathsKeepsPathsWhoseStatFails(t *testing.T) {
	stat := func(string) (fs.FileInfo, error) { return nil, errors.New("permission denied") }
	if stale := stalePaths([]string{"/somewhere/Throwntom.app"}, stat); len(stale) != 0 {
		t.Fatalf("stale = %v, want none when stat fails for a reason other than absence", stale)
	}
}

func TestStalePathsIgnoresRelativePaths(t *testing.T) {
	stat := func(string) (fs.FileInfo, error) { return nil, fs.ErrNotExist }
	if stale := stalePaths([]string{"macos/.build/Throwntom.app", ""}, stat); len(stale) != 0 {
		t.Fatalf("stale = %v, want none for non-absolute paths", stale)
	}
}

func TestListReportsEveryRegistrationWithItsState(t *testing.T) {
	var out, errOut bytes.Buffer
	env := environment{
		dump:       func() (string, error) { return dump, nil },
		stat:       fixtureStat,
		unregister: func(string) error { t.Fatal("list must not unregister"); return nil },
	}
	if code := run([]string{"list"}, &out, &errOut, env); code != 0 {
		t.Fatalf("exit = %d, stderr = %q", code, errOut.String())
	}
	text := out.String()
	if !strings.Contains(text, "stale  /gone/worktree/macos/.build/Throwntom.app") {
		t.Errorf("missing stale line in:\n%s", text)
	}
	if !strings.Contains(text, "live   /live/checkout/macos/.build/Throwntom.app") {
		t.Errorf("missing live line in:\n%s", text)
	}
}

func TestPruneUnregistersOnlyStalePaths(t *testing.T) {
	var out, errOut bytes.Buffer
	var unregistered []string
	env := environment{
		dump: func() (string, error) { return dump, nil },
		stat: fixtureStat,
		unregister: func(path string) error {
			unregistered = append(unregistered, path)
			return nil
		},
	}
	if code := run([]string{"prune"}, &out, &errOut, env); code != 0 {
		t.Fatalf("exit = %d, stderr = %q", code, errOut.String())
	}
	if len(unregistered) != 1 || unregistered[0] != "/gone/worktree/macos/.build/Throwntom.app" {
		t.Fatalf("unregistered = %v, want only the gone worktree path", unregistered)
	}
}

func TestPruneIsSilentWhenNothingIsStale(t *testing.T) {
	var out, errOut bytes.Buffer
	env := environment{
		dump:       func() (string, error) { return dump, nil },
		stat:       func(string) (fs.FileInfo, error) { return fakeInfo{}, nil },
		unregister: func(string) error { t.Fatal("nothing is stale; must not unregister"); return nil },
	}
	if code := run([]string{"prune"}, &out, &errOut, env); code != 0 {
		t.Fatalf("exit = %d, stderr = %q", code, errOut.String())
	}
	if out.Len() != 0 {
		t.Errorf("prune printed %q, want silence when the registrations are clean", out.String())
	}
}

// A failure to unregister one path must be reported but must not stop the rest.
func TestPruneReportsUnregisterFailures(t *testing.T) {
	var out, errOut bytes.Buffer
	env := environment{
		dump:       func() (string, error) { return dump, nil },
		stat:       func(string) (fs.FileInfo, error) { return nil, os.ErrNotExist },
		unregister: func(string) error { return errors.New("lsregister exploded") },
	}
	if code := run([]string{"prune"}, &out, &errOut, env); code != 1 {
		t.Fatalf("exit = %d, want 1", code)
	}
	if !strings.Contains(errOut.String(), "lsregister exploded") {
		t.Errorf("stderr = %q, want the underlying error", errOut.String())
	}
}

// A registration whose state cannot be established is reported as such rather
// than being passed off as live.
func TestListMarksUnresolvablePathsUnknown(t *testing.T) {
	var out, errOut bytes.Buffer
	env := environment{
		dump:       func() (string, error) { return dump, nil },
		stat:       func(string) (fs.FileInfo, error) { return nil, errors.New("permission denied") },
		unregister: func(string) error { t.Fatal("list must not unregister"); return nil },
	}
	if code := run([]string{"list"}, &out, &errOut, env); code != 0 {
		t.Fatalf("exit = %d, stderr = %q", code, errOut.String())
	}
	lines := strings.Split(strings.TrimSpace(out.String()), "\n")
	if len(lines) != 2 {
		t.Fatalf("got %d lines, want 2:\n%s", len(lines), out.String())
	}
	for _, line := range lines {
		if !strings.HasPrefix(line, "?") {
			t.Errorf("line claims a state it cannot establish: %q", line)
		}
	}
}

func TestDumpFailureIsReported(t *testing.T) {
	for _, command := range []string{"list", "prune"} {
		var out, errOut bytes.Buffer
		env := environment{
			dump:       func() (string, error) { return "", errors.New("lsregister unavailable") },
			stat:       fixtureStat,
			unregister: func(string) error { t.Fatal("must not unregister without a dump"); return nil },
		}
		if code := run([]string{command}, &out, &errOut, env); code != 1 {
			t.Errorf("%s exit = %d, want 1", command, code)
		}
		if !strings.Contains(errOut.String(), "lsregister unavailable") {
			t.Errorf("%s stderr = %q, want the underlying error", command, errOut.String())
		}
	}
}

func TestWrongArgCountPrintsUsage(t *testing.T) {
	env := environment{
		dump:       func() (string, error) { t.Fatal("must not read the database"); return "", nil },
		stat:       fixtureStat,
		unregister: func(string) error { t.Fatal("must not unregister"); return nil },
	}
	for _, args := range [][]string{{}, {"list", "prune"}} {
		var out, errOut bytes.Buffer
		if code := run(args, &out, &errOut, env); code != 2 {
			t.Errorf("args %v: exit = %d, want 2", args, code)
		}
		if !strings.Contains(errOut.String(), "usage:") {
			t.Errorf("args %v: stderr = %q, want usage", args, errOut.String())
		}
	}
}

func TestListReportsWhenNothingIsRegistered(t *testing.T) {
	var out, errOut bytes.Buffer
	env := environment{
		dump:       func() (string, error) { return "", nil },
		stat:       fixtureStat,
		unregister: func(string) error { t.Fatal("list must not unregister"); return nil },
	}
	if code := run([]string{"list"}, &out, &errOut, env); code != 0 {
		t.Fatalf("exit = %d, stderr = %q", code, errOut.String())
	}
	if !strings.Contains(out.String(), "no Launch Services registrations for "+bundleID) {
		t.Errorf("out = %q, want the no-registrations message", out.String())
	}
}

func TestUnknownCommandPrintsUsage(t *testing.T) {
	var out, errOut bytes.Buffer
	env := environment{
		dump:       func() (string, error) { t.Fatal("must not read the database"); return "", nil },
		stat:       fixtureStat,
		unregister: func(string) error { t.Fatal("must not unregister"); return nil },
	}
	if code := run([]string{"wat"}, &out, &errOut, env); code != 2 {
		t.Fatalf("exit = %d, want 2", code)
	}
	if !strings.Contains(errOut.String(), "usage:") {
		t.Errorf("stderr = %q, want usage", errOut.String())
	}
}
