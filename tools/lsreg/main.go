// Command lsreg reports and prunes Launch Services registrations for Throwntom.
//
// Launch Services keys registrations on the bundle id, so every worktree that
// builds Throwntom.app adds another registration for com.jwp23.throwntom, and
// deleting the worktree does not remove it. The dead entries accumulate and
// outlive the directories they name, leaving macOS free to resolve the app
// through a bundle that is no longer on disk.
package main

import (
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
)

// bundleID is fixed rather than a flag: this tool exists to clean up after
// Throwntom's own builds, and no invocation should be able to aim it elsewhere.
const bundleID = "com.jwp23.throwntom"

const lsregister = "/System/Library/Frameworks/CoreServices.framework/Versions/A/" +
	"Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

const usage = `usage: lsreg <list|prune>
  list   every Launch Services registration for ` + bundleID + `, marked live or stale
  prune  unregister the stale ones: registrations whose bundle is no longer on disk
`

// environment is the tool's contact with the machine, injected so the selection
// logic can be tested without reading or mutating the real database.
type environment struct {
	dump       func() (string, error)
	stat       func(string) (fs.FileInfo, error)
	unregister func(path string) error
}

func main() {
	env := environment{dump: dumpDatabase, stat: os.Stat, unregister: unregisterPath}
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr, env))
}

func run(args []string, stdout, stderr io.Writer, env environment) int {
	if len(args) != 1 {
		_, _ = fmt.Fprint(stderr, usage)
		return 2
	}
	switch args[0] {
	case "list":
		return list(stdout, stderr, env)
	case "prune":
		return prune(stdout, stderr, env)
	default:
		_, _ = fmt.Fprint(stderr, usage)
		return 2
	}
}

func list(stdout, stderr io.Writer, env environment) int {
	dump, err := env.dump()
	if err != nil {
		_, _ = fmt.Fprintln(stderr, err)
		return 1
	}
	paths := registeredPaths(dump)
	if len(paths) == 0 {
		_, _ = fmt.Fprintf(stdout, "no Launch Services registrations for %s\n", bundleID)
		return 0
	}
	stale := make(map[string]bool, len(paths))
	for _, path := range stalePaths(paths, env.stat) {
		stale[path] = true
	}
	for _, path := range paths {
		state := "live "
		if stale[path] {
			state = "stale"
		}
		_, _ = fmt.Fprintf(stdout, "%s  %s\n", state, path)
	}
	return 0
}

func prune(stdout, stderr io.Writer, env environment) int {
	dump, err := env.dump()
	if err != nil {
		_, _ = fmt.Fprintln(stderr, err)
		return 1
	}
	failed := false
	for _, path := range stalePaths(registeredPaths(dump), env.stat) {
		if err := env.unregister(path); err != nil {
			_, _ = fmt.Fprintf(stderr, "lsreg: %s: %v\n", path, err)
			failed = true
			continue
		}
		_, _ = fmt.Fprintf(stdout, "unregistered stale %s: %s\n", bundleID, path)
	}
	if failed {
		return 1
	}
	return 0
}

// Records in an lsregister dump are separated by a rule of dashes.
var recordSeparator = regexp.MustCompile(`(?m)^-{5,}$`)

// A dumped path carries a trailing store handle, as in "/Apps/X.app (0x18bc)".
var pathLine = regexp.MustCompile(`(?m)^path:\s+(.*?)(?:\s+\(0x[0-9a-fA-F]+\))?$`)

// Only a record's own identifier field names its bundle id. Fields such as
// codeInfoID and activityTypes can quote the same string while describing a
// different bundle, so matching on them would put foreign paths in range.
var identifierLine = regexp.MustCompile(`(?m)^identifier:\s+(\S+)\s*$`)

// registeredPaths returns the bundle path of every record in an lsregister dump
// whose identifier is exactly Throwntom's bundle id, in the order dumped.
func registeredPaths(dump string) []string {
	var paths []string
	for _, record := range recordSeparator.Split(dump, -1) {
		id := identifierLine.FindStringSubmatch(record)
		if id == nil || !strings.EqualFold(id[1], bundleID) {
			continue
		}
		if path := pathLine.FindStringSubmatch(record); path != nil {
			paths = append(paths, strings.TrimSpace(path[1]))
		}
	}
	return paths
}

// stalePaths returns the registered paths that are absent from disk. Every
// uncertainty resolves to "keep": a path is stale only when it is absolute and
// stat reports it does not exist. A stat that fails for any other reason leaves
// the registration alone, so no live bundle can be unregistered by accident.
func stalePaths(paths []string, stat func(string) (fs.FileInfo, error)) []string {
	var stale []string
	for _, path := range paths {
		if !filepath.IsAbs(path) {
			continue
		}
		if _, err := stat(path); errors.Is(err, fs.ErrNotExist) {
			stale = append(stale, path)
		}
	}
	return stale
}

func dumpDatabase() (string, error) {
	out, err := exec.Command(lsregister, "-dump").Output()
	if err != nil {
		return "", fmt.Errorf("lsregister -dump: %w", err)
	}
	return string(out), nil
}

func unregisterPath(path string) error {
	if !filepath.IsAbs(path) {
		return fmt.Errorf("refusing to unregister non-absolute path %q", path)
	}
	if out, err := exec.Command(lsregister, "-u", path).CombinedOutput(); err != nil {
		return fmt.Errorf("lsregister -u: %w: %s", err, strings.TrimSpace(string(out)))
	}
	return nil
}
