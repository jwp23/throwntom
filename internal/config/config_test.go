package config

import (
	"os"
	"path/filepath"
	"testing"
)

const fmtUnexpectedErr = "unexpected error: %v"

func TestDefaultConfig(t *testing.T) {
	cfg := Default()
	if cfg.Schedule.Time != "09:15" {
		t.Fatalf("expected default time 09:15, got %s", cfg.Schedule.Time)
	}
	if !cfg.MorningReminderPending {
		t.Fatal("expected morning reminder pending to default to true")
	}
	if !cfg.Emoji {
		t.Fatal("expected emoji to default to true")
	}
}

func TestDefaultCycleCadence(t *testing.T) {
	cfg := Default()
	if cfg.WorkMinutes != 25 || cfg.ShortBreakMinutes != 5 || cfg.LongBreakMinutes != 15 || cfg.LongBreakEvery != 4 {
		t.Fatalf("unexpected defaults: %+v", cfg)
	}
}

func TestLoadRejectsInvalidTime(t *testing.T) {
	_, err := LoadBytes([]byte(`schedule_time = "9:15"\nschedule_days = ["Mon"]`))
	if err == nil {
		t.Fatal("expected invalid time format error")
	}
}

func TestLoadBytesParsesToml(t *testing.T) {
	raw := []byte(`
work_minutes = 30
short_break_minutes = 6
long_break_minutes = 20
long_break_every = 3
repeat_secs = 15
schedule_time = "09:45"
schedule_days = ["Mon","Tue","Wed"]
sound_command = ["paplay","/tmp/sound.oga"]
morning_reminder_pending = false
`)
	cfg, err := LoadBytes(raw)
	if err != nil {
		t.Fatalf(fmtUnexpectedErr, err)
	}
	if cfg.LongBreakEvery != 3 || cfg.Schedule.Time != "09:45" {
		t.Fatalf("unexpected parsed config: %+v", cfg)
	}
	if len(cfg.SoundCommand) != 2 || cfg.SoundCommand[0] != "paplay" {
		t.Fatalf("unexpected sound command: %v", cfg.SoundCommand)
	}
	if cfg.MorningReminderPending {
		t.Fatal("expected morning reminder pending to parse as false")
	}
}

func TestEmojiDefaultsTrueAndCanBeDisabled(t *testing.T) {
	cfg, err := LoadBytes([]byte(`emoji = false`))
	if err != nil {
		t.Fatalf(fmtUnexpectedErr, err)
	}
	if cfg.Emoji {
		t.Fatal("expected emoji to be false when explicitly set")
	}
}

func TestLoadAcceptsValidTimeAndMergesDefaults(t *testing.T) {
	cfg, err := LoadBytes([]byte(`schedule_time = "10:30"`))
	if err != nil {
		t.Fatalf(fmtUnexpectedErr, err)
	}
	if cfg.Schedule.Time != "10:30" {
		t.Fatalf("expected overridden time 10:30, got %s", cfg.Schedule.Time)
	}
	if len(cfg.Schedule.Days) != 5 {
		t.Fatalf("expected default weekdays, got %v", cfg.Schedule.Days)
	}
}

func TestLoadRejectsOutOfRangeTime(t *testing.T) {
	_, err := LoadBytes([]byte(`schedule_time = "99:99"`))
	if err == nil {
		t.Fatal("expected out-of-range schedule_time error")
	}
}

func TestLoadRejectsUnknownScheduleDay(t *testing.T) {
	_, err := LoadBytes([]byte(`schedule_days = ["Monday"]`))
	if err == nil {
		t.Fatal("expected unknown schedule day error")
	}
}

func TestLoadFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.toml")
	if err := os.WriteFile(path, []byte(`schedule_time = "11:45"`), 0o644); err != nil {
		t.Fatalf("write config: %v", err)
	}
	cfg, err := LoadFile(path)
	if err != nil {
		t.Fatalf(fmtUnexpectedErr, err)
	}
	if cfg.Schedule.Time != "11:45" {
		t.Fatalf("expected overridden time, got %s", cfg.Schedule.Time)
	}
}

func TestLoadRejectsEmptySoundCommandPart(t *testing.T) {
	_, err := LoadBytes([]byte(`sound_command = ["", "/tmp/sound.oga"]`))
	if err == nil {
		t.Fatal("expected empty sound command part error")
	}
}
