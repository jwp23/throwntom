package config

import (
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"strings"
	"testing"
)

// documentedKeys is every setting a user can put in config.toml. The template
// must document all of them, so a new setting that skips the template fails
// here rather than going unnoticed.
var documentedKeys = []string{
	"work_minutes",
	"short_break_minutes",
	"long_break_minutes",
	"long_break_every",
	"days",
	"time",
	"repeat_secs",
	"repeat_limit_secs",
	"sound_command",
	"morning_reminder_pending",
	"emoji",
	"tier_low",
	"tier_mid",
}

func TestTemplateIsFullyCommentedOut(t *testing.T) {
	for i, line := range strings.Split(Template, "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}
		t.Fatalf("template line %d is not commented out: %q", i+1, line)
	}
}

func TestTemplateParsesAsDefaults(t *testing.T) {
	cfg, err := LoadBytes([]byte(Template))
	if err != nil {
		t.Fatalf("parse template: %v", err)
	}
	if !reflect.DeepEqual(cfg, Default()) {
		t.Fatalf("template parses to %+v, want the defaults %+v", cfg, Default())
	}
}

func TestTemplateDocumentsEverySetting(t *testing.T) {
	for _, key := range documentedKeys {
		if !strings.Contains(Template, key) {
			t.Errorf("template does not mention %q", key)
		}
	}
	for _, section := range []string{"[pomodoro]", "[[schedule]]", "[stats]"} {
		if !strings.Contains(Template, section) {
			t.Errorf("template does not mention section %q", section)
		}
	}
}

// settingLine matches a commented-out setting or section header — the lines
// that state a default — and not the prose around them.
var settingLine = regexp.MustCompile(`^#\s?(\[\[?[a-z_]+\]\]?|[a-z_]+ = .*)$`)

// TestTemplateCommentedDefaultsAreTheRealDefaults uncomments every setting
// line and checks the result is exactly the default config, so a documented
// value can never drift from the code's default.
func TestTemplateCommentedDefaultsAreTheRealDefaults(t *testing.T) {
	var uncommented []string
	for _, line := range strings.Split(Template, "\n") {
		trimmed := strings.TrimSpace(line)
		if m := settingLine.FindStringSubmatch(trimmed); m != nil {
			uncommented = append(uncommented, m[1])
		}
	}
	body := strings.Join(uncommented, "\n")
	cfg, err := LoadBytes([]byte(body))
	if err != nil {
		t.Fatalf("parse uncommented template: %v\n%s", err, body)
	}
	if !reflect.DeepEqual(normalize(cfg), normalize(Default())) {
		t.Fatalf("uncommented template is %+v, want the defaults %+v", cfg, Default())
	}
}

// normalize erases the difference between an unset sound_command and one the
// template spells out as an empty list; nothing else distinguishes them.
func normalize(cfg Config) Config {
	if len(cfg.SoundCommand) == 0 {
		cfg.SoundCommand = nil
	}
	return cfg
}

func TestEnsureFileWritesTemplateWhenMissing(t *testing.T) {
	path := filepath.Join(t.TempDir(), "nested", "config.toml")

	if err := EnsureFile(path); err != nil {
		t.Fatalf("EnsureFile: %v", err)
	}

	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read written config: %v", err)
	}
	if string(raw) != Template {
		t.Fatal("expected the template to be written verbatim")
	}
}

func TestEnsureFileLeavesAnExistingFileAlone(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.toml")
	existing := "[pomodoro]\nwork_minutes = 40\n"
	writeConfig(t, path, existing)

	if err := EnsureFile(path); err != nil {
		t.Fatalf("EnsureFile: %v", err)
	}

	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	if string(raw) != existing {
		t.Fatalf("expected the existing config untouched, got %q", raw)
	}
}
