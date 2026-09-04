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

// Off by default: raising the window over whatever the user is doing is a
// convenience some want and others would call an interruption, so it is opted
// into rather than out of.
func TestFloatWindowWhenWaitingDefaultsOffAndCanBeEnabled(t *testing.T) {
	if Default().FloatWindowWhenWaiting {
		t.Fatal("expected float_window_when_waiting to default to false")
	}
	cfg, err := LoadBytes([]byte(`float_window_when_waiting = true`))
	if err != nil {
		t.Fatalf(fmtUnexpectedErr, err)
	}
	if !cfg.FloatWindowWhenWaiting {
		t.Fatal("expected float_window_when_waiting to be true when explicitly set")
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
	assertDayTimes(t, raw, map[string]string{
		"Mon": "09:00", "Tue": "09:00", "Wed": "09:00",
		"Thu": "09:00", "Fri": "09:00",
	})
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

func assertDayTimes(t *testing.T, toml []byte, expected map[string]string) {
	t.Helper()
	cfg, err := LoadBytes(toml)
	if err != nil {
		t.Fatalf(fmtUnexpectedErr, err)
	}
	dt := ScheduleDayTimes(cfg.Schedule)
	for day, want := range expected {
		if dt[day] != want {
			t.Fatalf(fmtExpectedDayTime, day, want, dt[day])
		}
	}
	if len(dt) != len(expected) {
		t.Fatalf(fmtExpectedNEntries, len(expected), len(dt))
	}
}

var weekdayAt0900 = map[string]string{
	"Mon": "09:00", "Tue": "09:00", "Wed": "09:00",
	"Thu": "09:00", "Fri": "09:00",
}

func TestScheduleAliasExpansion(t *testing.T) {
	tests := []struct {
		name     string
		toml     string
		expected map[string]string
	}{
		{
			name:     "omitted days defaults to weekday",
			toml:     "[[schedule]]\ntime = \"09:00\"",
			expected: weekdayAt0900,
		},
		{
			name:     "weekday alias expands to Mon-Fri",
			toml:     "[[schedule]]\ndays = [\"weekday\"]\ntime = \"09:00\"",
			expected: weekdayAt0900,
		},
		{
			name: "weekend alias expands to Sat-Sun",
			toml: "[[schedule]]\ndays = [\"weekend\"]\ntime = \"10:00\"",
			expected: map[string]string{
				"Sat": "10:00", "Sun": "10:00",
			},
		},
		{
			name: "omitted days carve-out with Fri override",
			toml: "[[schedule]]\ntime = \"09:00\"\n\n[[schedule]]\ndays = [\"Fri\"]\ntime = \"10:00\"",
			expected: map[string]string{
				"Mon": "09:00", "Tue": "09:00", "Wed": "09:00",
				"Thu": "09:00", "Fri": "10:00",
			},
		},
		{
			name: "explicit weekday alias carve-out with Fri override",
			toml: "[[schedule]]\ndays = [\"weekday\"]\ntime = \"09:00\"\n\n[[schedule]]\ndays = [\"Fri\"]\ntime = \"10:00\"",
			expected: map[string]string{
				"Mon": "09:00", "Tue": "09:00", "Wed": "09:00",
				"Thu": "09:00", "Fri": "10:00",
			},
		},
		{
			name: "mixed weekend + weekday default + Fri override",
			toml: "[[schedule]]\ndays = [\"weekend\"]\ntime = \"11:00\"\n\n[[schedule]]\ntime = \"09:00\"\n\n[[schedule]]\ndays = [\"Fri\"]\ntime = \"10:00\"",
			expected: map[string]string{
				"Mon": "09:00", "Tue": "09:00", "Wed": "09:00", "Thu": "09:00",
				"Fri": "10:00", "Sat": "11:00", "Sun": "11:00",
			},
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			assertDayTimes(t, []byte(tc.toml), tc.expected)
		})
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

func TestDefaultRepeatLimit(t *testing.T) {
	cfg := Default()
	if cfg.RepeatLimitSecs != 300 {
		t.Fatalf("expected default repeat limit of 300s, got %d", cfg.RepeatLimitSecs)
	}
}

func TestLoadBytesParsesRepeatLimit(t *testing.T) {
	cfg, err := LoadBytes([]byte("repeat_limit_secs = 90"))
	if err != nil {
		t.Fatalf(fmtUnexpectedErr, err)
	}
	if cfg.RepeatLimitSecs != 90 {
		t.Fatalf("expected repeat limit 90, got %d", cfg.RepeatLimitSecs)
	}
}

func TestLoadRejectsNonPositiveRepeatLimit(t *testing.T) {
	if _, err := LoadBytes([]byte("repeat_limit_secs = 0")); err == nil {
		t.Fatal("expected repeat_limit_secs validation error")
	}
}

// Lunch is a break the user chooses, so its length is theirs to set; an hour
// is the default working assumption.
func TestDefaultLunchMinutes(t *testing.T) {
	if got := Default().Pomodoro.LunchMinutes; got != 60 {
		t.Fatalf("default lunch_minutes is %d, want 60", got)
	}
}

func TestLoadBytesParsesLunchMinutes(t *testing.T) {
	cfg, err := LoadBytes([]byte("[pomodoro]\nlunch_minutes = 45\n"))
	if err != nil {
		t.Fatalf(fmtUnexpectedErr, err)
	}
	if cfg.Pomodoro.LunchMinutes != 45 {
		t.Fatalf("lunch_minutes is %d, want 45", cfg.Pomodoro.LunchMinutes)
	}
}

func TestLoadRejectsNonPositiveLunchMinutes(t *testing.T) {
	_, err := LoadBytes([]byte("[pomodoro]\nlunch_minutes = 0\n"))
	if err == nil {
		t.Fatal("expected lunch_minutes = 0 to be rejected")
	}
	if want := "lunch_minutes must be > 0"; err.Error() != want {
		t.Fatalf("error is %q, want %q", err, want)
	}
}
