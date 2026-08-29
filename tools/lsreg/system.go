package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

const lsregister = "/System/Library/Frameworks/CoreServices.framework/Versions/A/" +
	"Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

func main() {
	env := environment{dump: dumpDatabase, stat: os.Stat, unregister: unregisterPath}
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr, env))
}

func dumpDatabase() (string, error) {
	out, err := exec.Command(lsregister, "-dump").Output()
	if err != nil {
		var exit *exec.ExitError
		if errors.As(err, &exit) && len(exit.Stderr) > 0 {
			return "", fmt.Errorf("lsregister -dump: %w: %s", err, strings.TrimSpace(string(exit.Stderr)))
		}
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
