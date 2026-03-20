package config

import (
	"os"
	"path/filepath"
	"testing"
)

const fmtUnexpectedErr = "unexpected error: %v"
const fmtExpectedNEntries = "expected %d entries, got %d"
const fmtExpectedDayTime = "expected %s=%s, got %s"

func TestDefaultConfig(t *testing.T) {
	cfg := Default()
	if len(cfg.Schedule) != 1 {
		t.Fatalf("expected 1 default schedule entry, got %d", len(cfg.Schedule))
	}
	if cfg.Schedule[0].Time != "09:15" {
		t.Fatalf("expected default time 09:15, got %s", cfg.Schedule[0].Time)
	}
	if len(cfg.Schedule[0].Days) != 5 {
		t.Fatalf("expected 5 default days, got %d", len(cfg.Schedule[0].Days))
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
	if cfg.Pomodoro.WorkMinutes != 25 || cfg.Pomodoro.ShortBreakMinutes != 5 || cfg.Pomodoro.LongBreakMinutes != 15 || cfg.Pomodoro.LongBreakEvery != 4 {
		t.Fatalf("unexpected defaults: %+v", cfg)
	}
}

func TestLoadRejectsInvalidTime(t *testing.T) {
	_, err := LoadBytes([]byte("[[schedule]]\ntime = \"9:15\"\ndays = [\"Mon\"]"))
	if err == nil {
		t.Fatal("expected invalid time format error")
	}
}

func TestLoadBytesParsesToml(t *testing.T) {
	raw := []byte(`
repeat_secs = 15
sound_command = ["paplay", "/tmp/sound.oga"]
morning_reminder_pending = false

[pomodoro]
work_minutes = 30
short_break_minutes = 6
long_break_minutes = 20
long_break_every = 3

[[schedule]]
time = "09:45"
days = ["Mon", "Tue", "Wed"]
`)
	cfg, err := LoadBytes(raw)
	if err != nil {
		t.Fatalf(fmtUnexpectedErr, err)
	}
	if cfg.Pomodoro.LongBreakEvery != 3 || cfg.Schedule[0].Time != "09:45" {
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
	cfg, err := LoadBytes([]byte("[[schedule]]\ntime = \"10:30\"\ndays = [\"Mon\", \"Tue\", \"Wed\", \"Thu\", \"Fri\"]"))
	if err != nil {
		t.Fatalf(fmtUnexpectedErr, err)
	}
	if cfg.Schedule[0].Time != "10:30" {
		t.Fatalf("expected overridden time 10:30, got %s", cfg.Schedule[0].Time)
	}
	if len(cfg.Schedule[0].Days) != 5 {
		t.Fatalf("expected 5 days, got %v", cfg.Schedule[0].Days)
	}
}

func TestLoadRejectsOutOfRangeTime(t *testing.T) {
	_, err := LoadBytes([]byte("[[schedule]]\ntime = \"99:99\"\ndays = [\"Mon\"]"))
	if err == nil {
		t.Fatal("expected out-of-range schedule_time error")
	}
}

func TestLoadRejectsUnknownScheduleDay(t *testing.T) {
	_, err := LoadBytes([]byte("[[schedule]]\ndays = [\"Monday\"]\ntime = \"09:00\""))
	if err == nil {
		t.Fatal("expected unknown schedule day error")
	}
}

func TestLoadFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.toml")
	if err := os.WriteFile(path, []byte("[[schedule]]\ntime = \"11:45\"\ndays = [\"Mon\"]"), 0o644); err != nil {
		t.Fatalf("write config: %v", err)
	}
	cfg, err := LoadFile(path)
	if err != nil {
		t.Fatalf(fmtUnexpectedErr, err)
	}
	if cfg.Schedule[0].Time != "11:45" {
		t.Fatalf("expected overridden time, got %s", cfg.Schedule[0].Time)
	}
}

func TestLoadRejectsEmptySoundCommandPart(t *testing.T) {
	_, err := LoadBytes([]byte(`sound_command = ["", "/tmp/sound.oga"]`))
	if err == nil {
		t.Fatal("expected empty sound command part error")
	}
}

func TestLoadRejectsUnknownKey(t *testing.T) {
	_, err := LoadBytes([]byte(`bogus_key = 42`))
	if err == nil {
		t.Fatal("expected unknown key error")
	}
}

func TestDefaultStatsConfig(t *testing.T) {
	cfg := Default()
	if cfg.Stats.TierLow != 2 {
		t.Fatalf("expected default TierLow=2, got %d", cfg.Stats.TierLow)
	}
	if cfg.Stats.TierMid != 5 {
		t.Fatalf("expected default TierMid=5, got %d", cfg.Stats.TierMid)
	}
}

func TestStatsTiersParsed(t *testing.T) {
	raw := []byte(`
[stats]
tier_low = 3
tier_mid = 8
`)
	cfg, err := LoadBytes(raw)
	if err != nil {
		t.Fatalf(fmtUnexpectedErr, err)
	}
	if cfg.Stats.TierLow != 3 || cfg.Stats.TierMid != 8 {
		t.Fatalf("expected parsed tiers 3/8, got %d/%d", cfg.Stats.TierLow, cfg.Stats.TierMid)
	}
}

func TestTierLowLessThanMid(t *testing.T) {
	raw := []byte(`
[stats]
tier_low = 5
tier_mid = 3
`)
	_, err := LoadBytes(raw)
	if err == nil {
		t.Fatal("expected error when tier_low >= tier_mid")
	}
}

// --- New tests for [[schedule]] array-of-tables ---

func TestLoadMultipleScheduleGroups(t *testing.T) {
	raw := []byte(`
[[schedule]]
days = ["Mon", "Tue", "Wed", "Thu"]
time = "09:00"

[[schedule]]
days = ["Fri"]
time = "10:00"
`)
	cfg, err := LoadBytes(raw)
	if err != nil {
		t.Fatalf(fmtUnexpectedErr, err)
	}
	if len(cfg.Schedule) != 2 {
		t.Fatalf("expected 2 schedule entries, got %d", len(cfg.Schedule))
	}
	if cfg.Schedule[0].Time != "09:00" || cfg.Schedule[1].Time != "10:00" {
		t.Fatalf("unexpected times: %v", cfg.Schedule)
	}
}

func TestLoadRejectsDuplicateDaysAcrossGroups(t *testing.T) {
	raw := []byte(`
[[schedule]]
days = ["Mon", "Tue"]
time = "09:00"

[[schedule]]
days = ["Tue", "Wed"]
time = "10:00"
`)
	_, err := LoadBytes(raw)
	if err == nil {
		t.Fatal("expected error for duplicate day across groups")
	}
}

func TestEmptyDaysDefaultsToWeekday(t *testing.T) {
	raw := []byte(`
[[schedule]]
days = []
time = "09:00"
`)
	cfg, err := LoadBytes(raw)
	if err != nil {
		t.Fatalf(fmtUnexpectedErr, err)
	}
	dt := ScheduleDayTimes(cfg.Schedule)
	if len(dt) != 5 {
		t.Fatalf(fmtExpectedNEntries, 5, len(dt))
	}
	if dt["Mon"] != "09:00" {
		t.Fatalf("expected Mon=09:00, got %s", dt["Mon"])
	}
}

func TestLoadRejectsScheduleEntryWithMissingTime(t *testing.T) {
	raw := []byte(`
[[schedule]]
days = ["Mon"]
`)
	_, err := LoadBytes(raw)
	if err == nil {
		t.Fatal("expected error for schedule entry with missing time")
	}
}

func TestDefaultScheduleWhenNoScheduleProvided(t *testing.T) {
	cfg, err := LoadBytes([]byte(`repeat_secs = 10`))
	if err != nil {
		t.Fatalf(fmtUnexpectedErr, err)
	}
	if len(cfg.Schedule) != 1 {
		t.Fatalf("expected 1 default schedule entry, got %d", len(cfg.Schedule))
	}
	if cfg.Schedule[0].Time != "09:15" {
		t.Fatalf("expected default time 09:15, got %s", cfg.Schedule[0].Time)
	}
}

func TestScheduleDayTimes(t *testing.T) {
	entries := []ScheduleEntry{
		{Days: []string{"Mon", "Tue", "Wed", "Thu"}, Time: "09:00"},
		{Days: []string{"Fri"}, Time: "10:00"},
	}
	dt := ScheduleDayTimes(entries)
	if dt["Mon"] != "09:00" || dt["Fri"] != "10:00" {
		t.Fatalf("unexpected day-time map: %v", dt)
	}
	if len(dt) != 5 {
		t.Fatalf(fmtExpectedNEntries, 5, len(dt))
	}
}

// --- Tests for schedule day aliases and optional days ---

func TestOmittedDaysDefaultsToWeekday(t *testing.T) {
	raw := []byte(`
[[schedule]]
time = "09:00"
`)
	cfg, err := LoadBytes(raw)
	if err != nil {
		t.Fatalf(fmtUnexpectedErr, err)
	}
	dt := ScheduleDayTimes(cfg.Schedule)
	for _, day := range []string{"Mon", "Tue", "Wed", "Thu", "Fri"} {
		if dt[day] != "09:00" {
			t.Fatalf(fmtExpectedDayTime, day, "09:00", dt[day])
		}
	}
	if len(dt) != 5 {
		t.Fatalf(fmtExpectedNEntries, 5, len(dt))
	}
}

func TestWeekdayAliasExpandsToMonFri(t *testing.T) {
	raw := []byte(`
[[schedule]]
days = ["weekday"]
time = "09:00"
`)
	cfg, err := LoadBytes(raw)
	if err != nil {
		t.Fatalf(fmtUnexpectedErr, err)
	}
	dt := ScheduleDayTimes(cfg.Schedule)
	for _, day := range []string{"Mon", "Tue", "Wed", "Thu", "Fri"} {
		if dt[day] != "09:00" {
			t.Fatalf(fmtExpectedDayTime, day, "09:00", dt[day])
		}
	}
	if len(dt) != 5 {
		t.Fatalf(fmtExpectedNEntries, 5, len(dt))
	}
}

func TestWeekendAliasExpandsToSatSun(t *testing.T) {
	raw := []byte(`
[[schedule]]
days = ["weekend"]
time = "10:00"
`)
	cfg, err := LoadBytes(raw)
	if err != nil {
		t.Fatalf(fmtUnexpectedErr, err)
	}
	dt := ScheduleDayTimes(cfg.Schedule)
	for _, day := range []string{"Sat", "Sun"} {
		if dt[day] != "10:00" {
			t.Fatalf(fmtExpectedDayTime, day, "10:00", dt[day])
		}
	}
	if len(dt) != 2 {
		t.Fatalf(fmtExpectedNEntries, 2, len(dt))
	}
}

func TestAliasOverrideCarveOut(t *testing.T) {
	raw := []byte(`
[[schedule]]
time = "09:00"

[[schedule]]
days = ["Fri"]
time = "10:00"
`)
	cfg, err := LoadBytes(raw)
	if err != nil {
		t.Fatalf(fmtUnexpectedErr, err)
	}
	dt := ScheduleDayTimes(cfg.Schedule)
	for _, day := range []string{"Mon", "Tue", "Wed", "Thu"} {
		if dt[day] != "09:00" {
			t.Fatalf(fmtExpectedDayTime, day, "09:00", dt[day])
		}
	}
	if dt["Fri"] != "10:00" {
		t.Fatalf("expected Fri=10:00, got %s", dt["Fri"])
	}
	if len(dt) != 5 {
		t.Fatalf(fmtExpectedNEntries, 5, len(dt))
	}
}

func TestExplicitWeekdayAliasOverrideCarveOut(t *testing.T) {
	raw := []byte(`
[[schedule]]
days = ["weekday"]
time = "09:00"

[[schedule]]
days = ["Fri"]
time = "10:00"
`)
	cfg, err := LoadBytes(raw)
	if err != nil {
		t.Fatalf(fmtUnexpectedErr, err)
	}
	dt := ScheduleDayTimes(cfg.Schedule)
	for _, day := range []string{"Mon", "Tue", "Wed", "Thu"} {
		if dt[day] != "09:00" {
			t.Fatalf(fmtExpectedDayTime, day, "09:00", dt[day])
		}
	}
	if dt["Fri"] != "10:00" {
		t.Fatalf("expected Fri=10:00, got %s", dt["Fri"])
	}
	if len(dt) != 5 {
		t.Fatalf(fmtExpectedNEntries, 5, len(dt))
	}
}

func TestAliasFullyOverriddenErrors(t *testing.T) {
	raw := []byte(`
[[schedule]]
days = ["weekday"]
time = "09:00"

[[schedule]]
days = ["Mon"]
time = "08:00"

[[schedule]]
days = ["Tue"]
time = "08:30"

[[schedule]]
days = ["Wed"]
time = "09:30"

[[schedule]]
days = ["Thu"]
time = "10:00"

[[schedule]]
days = ["Fri"]
time = "10:30"
`)
	_, err := LoadBytes(raw)
	if err == nil {
		t.Fatal("expected error when alias is fully overridden")
	}
}

func TestScheduleDayTimesAfterNormalization(t *testing.T) {
	raw := []byte(`
[[schedule]]
days = ["weekend"]
time = "11:00"

[[schedule]]
time = "09:00"

[[schedule]]
days = ["Fri"]
time = "10:00"
`)
	cfg, err := LoadBytes(raw)
	if err != nil {
		t.Fatalf(fmtUnexpectedErr, err)
	}
	dt := ScheduleDayTimes(cfg.Schedule)
	expected := map[string]string{
		"Mon": "09:00", "Tue": "09:00", "Wed": "09:00", "Thu": "09:00",
		"Fri": "10:00", "Sat": "11:00", "Sun": "11:00",
	}
	for day, want := range expected {
		if dt[day] != want {
			t.Fatalf(fmtExpectedDayTime, day, want, dt[day])
		}
	}
	if len(dt) != 7 {
		t.Fatalf(fmtExpectedNEntries, 7, len(dt))
	}
}
