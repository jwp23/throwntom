package config

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	"github.com/BurntSushi/toml"
)

var timePattern = regexp.MustCompile(`^[0-9]{2}:[0-9]{2}$`)

type ScheduleEntry struct {
	Days []string `toml:"days"`
	Time string   `toml:"time"`
}

type Config struct {
	Pomodoro struct {
		WorkMinutes       int `toml:"work_minutes"`
		ShortBreakMinutes int `toml:"short_break_minutes"`
		LongBreakMinutes  int `toml:"long_break_minutes"`
		LunchMinutes      int `toml:"lunch_minutes"`
		LongBreakEvery    int `toml:"long_break_every"`
	} `toml:"pomodoro"`
	Schedule               []ScheduleEntry `toml:"schedule"`
	RepeatSecs             int             `toml:"repeat_secs"`
	RepeatLimitSecs        int             `toml:"repeat_limit_secs"`
	SoundCommand           []string        `toml:"sound_command"`
	MorningReminderPending bool            `toml:"morning_reminder_pending"`
	Emoji                  bool            `toml:"emoji"`
	// FloatWindowWhenWaiting asks a client to keep its window above other
	// applications' windows while a reminder is outstanding. Nothing here acts
	// on it: it is presentation, which belongs to the client (ADR-003), and
	// only the macOS window app implements it. It lives in this file because
	// this file is where the user's settings are, and because LoadBytes
	// rejects keys the struct does not name.
	FloatWindowWhenWaiting bool `toml:"float_window_when_waiting"`
	// PausedTooLongMinutes is how long a pause may last before the daemon
	// calls it forgotten and publishes that in its state. What a client makes
	// of it is the client's (ADR-003): the macOS app bounces its Dock icon.
	PausedTooLongMinutes int `toml:"paused_too_long_minutes"`
	// BounceDockWhenPaused is whether the macOS app should bounce its Dock
	// icon once a pause counts as forgotten. Like FloatWindowWhenWaiting this
	// is presentation, which belongs to the client (ADR-003): the daemon goes
	// on publishing paused_too_long on its own clock regardless of this
	// setting. On by default, unlike FloatWindowWhenWaiting: the bounce is
	// the whole point of paused_too_long_minutes, so a config that says
	// nothing keeps it.
	BounceDockWhenPaused bool `toml:"bounce_dock_when_paused"`
	Stats                struct {
		TierLow int `toml:"tier_low"`
		TierMid int `toml:"tier_mid"`
	} `toml:"stats"`
}

func Default() Config {
	var cfg Config
	cfg.Schedule = []ScheduleEntry{{
		Days: []string{"Mon", "Tue", "Wed", "Thu", "Fri"},
		Time: "09:15",
	}}
	cfg.Pomodoro.WorkMinutes = 25
	cfg.Pomodoro.ShortBreakMinutes = 5
	cfg.Pomodoro.LongBreakMinutes = 15
	cfg.Pomodoro.LunchMinutes = 60
	cfg.Pomodoro.LongBreakEvery = 4
	cfg.RepeatSecs = 20
	cfg.RepeatLimitSecs = 300
	cfg.MorningReminderPending = true
	cfg.Emoji = true
	cfg.PausedTooLongMinutes = 10
	cfg.BounceDockWhenPaused = true
	cfg.Stats.TierLow = 2
	cfg.Stats.TierMid = 5
	return cfg
}

func LoadBytes(b []byte) (Config, error) {
	cfg := Default()
	// Clear default schedule before decode — TOML array-of-tables appends
	// to existing slices, so we must start empty to avoid merging defaults
	// with user-provided entries.
	cfg.Schedule = nil
	md, err := toml.Decode(string(b), &cfg)
	if err != nil {
		return Config{}, fmt.Errorf("parse config: %w", err)
	}
	if undecoded := md.Undecoded(); len(undecoded) > 0 {
		return Config{}, fmt.Errorf("unknown key %q", undecoded[0])
	}
	if len(cfg.Schedule) == 0 {
		cfg.Schedule = Default().Schedule
	}
	normalized, err := normalizeSchedule(cfg.Schedule)
	if err != nil {
		return Config{}, err
	}
	cfg.Schedule = normalized
	if err := validate(cfg); err != nil {
		return Config{}, err
	}
	return cfg, nil
}

func LoadFile(path string) (Config, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return Config{}, fmt.Errorf("read config file %q: %w", path, err)
	}
	return LoadBytes(b)
}

func ScheduleDayTimes(entries []ScheduleEntry) map[string]string {
	result := make(map[string]string)
	for _, e := range entries {
		for _, day := range e.Days {
			result[day] = e.Time
		}
	}
	return result
}

func validate(cfg Config) error {
	if cfg.Pomodoro.WorkMinutes <= 0 {
		return fmt.Errorf("work_minutes must be > 0")
	}
	if cfg.Pomodoro.ShortBreakMinutes <= 0 {
		return fmt.Errorf("short_break_minutes must be > 0")
	}
	if cfg.Pomodoro.LongBreakMinutes <= 0 {
		return fmt.Errorf("long_break_minutes must be > 0")
	}
	if cfg.Pomodoro.LunchMinutes <= 0 {
		return fmt.Errorf("lunch_minutes must be > 0")
	}
	if cfg.Pomodoro.LongBreakEvery <= 0 {
		return fmt.Errorf("long_break_every must be > 0")
	}
	if cfg.RepeatSecs <= 0 {
		return fmt.Errorf("repeat_secs must be > 0")
	}
	if cfg.RepeatLimitSecs <= 0 {
		return fmt.Errorf("repeat_limit_secs must be > 0")
	}
	if cfg.PausedTooLongMinutes <= 0 {
		return fmt.Errorf("paused_too_long_minutes must be > 0")
	}
	if len(cfg.Schedule) == 0 {
		return fmt.Errorf("at least one [[schedule]] entry is required")
	}
	if err := validateScheduleEntries(cfg.Schedule); err != nil {
		return err
	}
	if err := validateSoundCommand(cfg.SoundCommand); err != nil {
		return err
	}
	if cfg.Stats.TierLow <= 0 || cfg.Stats.TierMid <= 0 {
		return fmt.Errorf("stats tier_low and tier_mid must be > 0")
	}
	if cfg.Stats.TierLow >= cfg.Stats.TierMid {
		return fmt.Errorf("stats tier_low must be less than tier_mid")
	}
	return nil
}

func validateScheduleEntries(entries []ScheduleEntry) error {
	seen := make(map[string]bool)
	for i, entry := range entries {
		if entry.Time == "" {
			return fmt.Errorf("schedule[%d]: time is required", i)
		}
		if !timePattern.MatchString(entry.Time) {
			return fmt.Errorf("invalid schedule_time %q: expected HH:MM", entry.Time)
		}
		if err := validateHHMMRange(entry.Time); err != nil {
			return fmt.Errorf("invalid schedule_time %q: %w", entry.Time, err)
		}
		for _, day := range entry.Days {
			if !isSupportedWeekday(day) {
				return fmt.Errorf("invalid schedule day %q: expected Sun,Mon,Tue,Wed,Thu,Fri,Sat", day)
			}
			lower := strings.ToLower(day)
			if seen[lower] {
				return fmt.Errorf("duplicate schedule day %q across groups", day)
			}
			seen[lower] = true
		}
	}
	return nil
}

func validateSoundCommand(parts []string) error {
	for i, part := range parts {
		if strings.TrimSpace(part) == "" {
			return fmt.Errorf("sound_command[%d] must be a non-empty string", i)
		}
	}
	return nil
}

func validateHHMMRange(hhmm string) error {
	parts := strings.Split(hhmm, ":")
	if len(parts) != 2 {
		return fmt.Errorf("expected HH:MM")
	}
	hour, err := strconv.Atoi(parts[0])
	if err != nil || hour < 0 || hour > 23 {
		return fmt.Errorf("hour must be between 00 and 23")
	}
	minute, err := strconv.Atoi(parts[1])
	if err != nil || minute < 0 || minute > 59 {
		return fmt.Errorf("minute must be between 00 and 59")
	}
	return nil
}

func isSupportedWeekday(day string) bool {
	switch strings.ToLower(day) {
	case "sun", "mon", "tue", "wed", "thu", "fri", "sat",
		"weekday", "weekend":
		return true
	default:
		return false
	}
}

func isAlias(day string) bool {
	switch strings.ToLower(day) {
	case "weekday", "weekend":
		return true
	default:
		return false
	}
}

func expandAlias(day string) []string {
	switch strings.ToLower(day) {
	case "weekday":
		return []string{"Mon", "Tue", "Wed", "Thu", "Fri"}
	case "weekend":
		return []string{"Sat", "Sun"}
	default:
		return []string{day}
	}
}

func normalizeSchedule(entries []ScheduleEntry) ([]ScheduleEntry, error) {
	defaultEmptyDays(entries)
	concrete := collectConcreteDays(entries)
	return expandEntries(entries, concrete)
}

func defaultEmptyDays(entries []ScheduleEntry) {
	for i := range entries {
		if len(entries[i].Days) == 0 {
			entries[i].Days = []string{"weekday"}
		}
	}
}

func collectConcreteDays(entries []ScheduleEntry) map[string]bool {
	concrete := make(map[string]bool)
	for _, e := range entries {
		for _, day := range e.Days {
			if !isAlias(day) {
				concrete[strings.ToLower(day)] = true
			}
		}
	}
	return concrete
}

func expandEntries(entries []ScheduleEntry, concrete map[string]bool) ([]ScheduleEntry, error) {
	result := make([]ScheduleEntry, 0, len(entries))
	for _, e := range entries {
		expanded := expandDays(e.Days, concrete)
		if len(expanded) == 0 {
			return nil, fmt.Errorf("schedule alias %q expands to zero days after exclusions", e.Days[0])
		}
		result = append(result, ScheduleEntry{Days: expanded, Time: e.Time})
	}
	return result, nil
}

func expandDays(days []string, concrete map[string]bool) []string {
	var expanded []string
	for _, day := range days {
		if isAlias(day) {
			for _, d := range expandAlias(day) {
				if !concrete[strings.ToLower(d)] {
					expanded = append(expanded, d)
				}
			}
		} else {
			expanded = append(expanded, day)
		}
	}
	return expanded
}

// LoadDefault loads the config at path, or the default config file when path
// is empty. A missing default config file is not an error; it yields Default().
func LoadDefault(path string) (Config, error) {
	if path == "" {
		defaultPath, err := DirPath("config.toml")
		if err != nil {
			return Config{}, err
		}
		cfg, err := LoadFile(defaultPath)
		if err == nil {
			return cfg, nil
		}
		if errors.Is(err, os.ErrNotExist) {
			return Default(), nil
		}
		return Config{}, err
	}
	return LoadFile(path)
}

// DirPath returns the path of filename inside the user's throwntom config directory.
func DirPath(filename string) (string, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve home directory: %w", err)
	}
	return filepath.Join(homeDir, ".config", "throwntom", filename), nil
}
