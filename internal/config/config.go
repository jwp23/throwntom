package config

import (
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"
)

var timePattern = regexp.MustCompile(`^[0-9]{2}:[0-9]{2}$`)

type Config struct {
	Schedule struct {
		Days []string
		Time string
	}
	WorkMinutes            int
	ShortBreakMinutes      int
	LongBreakMinutes       int
	LongBreakEvery         int
	RepeatSecs             int
	SoundCommand           []string
	MorningReminderPending bool
}

func Default() Config {
	var cfg Config
	cfg.Schedule.Days = []string{"Mon", "Tue", "Wed", "Thu", "Fri"}
	cfg.Schedule.Time = "09:15"
	cfg.WorkMinutes = 25
	cfg.ShortBreakMinutes = 5
	cfg.LongBreakMinutes = 15
	cfg.LongBreakEvery = 4
	cfg.RepeatSecs = 20
	cfg.MorningReminderPending = true
	return cfg
}

func LoadBytes(b []byte) (Config, error) {
	cfg := Default()
	if err := parseTOMLInto(&cfg, string(b)); err != nil {
		return Config{}, err
	}
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

func validate(cfg Config) error {
	if !timePattern.MatchString(cfg.Schedule.Time) {
		return fmt.Errorf("invalid schedule_time %q: expected HH:MM", cfg.Schedule.Time)
	}
	if err := validateHHMMRange(cfg.Schedule.Time); err != nil {
		return fmt.Errorf("invalid schedule_time %q: %w", cfg.Schedule.Time, err)
	}
	if cfg.WorkMinutes <= 0 {
		return fmt.Errorf("work_minutes must be > 0")
	}
	if cfg.ShortBreakMinutes <= 0 {
		return fmt.Errorf("short_break_minutes must be > 0")
	}
	if cfg.LongBreakMinutes <= 0 {
		return fmt.Errorf("long_break_minutes must be > 0")
	}
	if cfg.LongBreakEvery <= 0 {
		return fmt.Errorf("long_break_every must be > 0")
	}
	if cfg.RepeatSecs <= 0 {
		return fmt.Errorf("repeat_secs must be > 0")
	}
	if len(cfg.Schedule.Days) == 0 {
		return fmt.Errorf("schedule_days must contain at least one day")
	}
	if len(cfg.SoundCommand) > 0 {
		for i, part := range cfg.SoundCommand {
			if strings.TrimSpace(part) == "" {
				return fmt.Errorf("sound_command[%d] must be a non-empty string", i)
			}
		}
	}
	for _, day := range cfg.Schedule.Days {
		if !isSupportedWeekday(day) {
			return fmt.Errorf("invalid schedule day %q: expected Sun,Mon,Tue,Wed,Thu,Fri,Sat", day)
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
	case "sun", "mon", "tue", "wed", "thu", "fri", "sat":
		return true
	default:
		return false
	}
}

func parseTOMLInto(cfg *Config, raw string) error {
	if strings.TrimSpace(raw) == "" {
		return nil
	}
	lines := strings.Split(raw, "\n")
	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}
		parts := strings.SplitN(trimmed, "=", 2)
		if len(parts) != 2 {
			return fmt.Errorf("line %d: expected key = value", i+1)
		}
		key := strings.TrimSpace(parts[0])
		val := strings.TrimSpace(parts[1])
		if err := applyKV(cfg, key, val); err != nil {
			return fmt.Errorf("line %d: %w", i+1, err)
		}
	}
	return nil
}

var configSetters = map[string]func(cfg *Config, val string) error{
	"work_minutes": func(cfg *Config, val string) error {
		return setIntField(&cfg.WorkMinutes, val)
	},
	"short_break_minutes": func(cfg *Config, val string) error {
		return setIntField(&cfg.ShortBreakMinutes, val)
	},
	"long_break_minutes": func(cfg *Config, val string) error {
		return setIntField(&cfg.LongBreakMinutes, val)
	},
	"long_break_every": func(cfg *Config, val string) error {
		return setIntField(&cfg.LongBreakEvery, val)
	},
	"repeat_secs": func(cfg *Config, val string) error {
		return setIntField(&cfg.RepeatSecs, val)
	},
	"schedule_time": func(cfg *Config, val string) error {
		return setStringField(&cfg.Schedule.Time, val)
	},
	"schedule_days": func(cfg *Config, val string) error {
		return setStringSliceField(&cfg.Schedule.Days, val)
	},
	"sound_command": func(cfg *Config, val string) error {
		return setStringSliceField(&cfg.SoundCommand, val)
	},
	"morning_reminder_pending": func(cfg *Config, val string) error {
		return setBoolField(&cfg.MorningReminderPending, val)
	},
}

func applyKV(cfg *Config, key, val string) error {
	setter, ok := configSetters[key]
	if !ok {
		return fmt.Errorf("unknown key %q", key)
	}
	return setter(cfg, val)
}

func setIntField(field *int, val string) error {
	n, err := parseInt(val)
	if err != nil {
		return err
	}
	*field = n
	return nil
}

func setStringField(field *string, val string) error {
	s, err := parseQuotedString(val)
	if err != nil {
		return err
	}
	*field = s
	return nil
}

func setStringSliceField(field *[]string, val string) error {
	items, err := parseStringArray(val)
	if err != nil {
		return err
	}
	*field = items
	return nil
}

func setBoolField(field *bool, val string) error {
	b, err := parseBool(val)
	if err != nil {
		return err
	}
	*field = b
	return nil
}

func parseInt(val string) (int, error) {
	n, err := strconv.Atoi(strings.TrimSpace(val))
	if err != nil {
		return 0, fmt.Errorf("invalid integer %q", val)
	}
	return n, nil
}

func parseQuotedString(val string) (string, error) {
	v := strings.TrimSpace(val)
	if len(v) < 2 || v[0] != '"' || v[len(v)-1] != '"' {
		return "", fmt.Errorf("expected quoted string, got %q", val)
	}
	return v[1 : len(v)-1], nil
}

func parseBool(val string) (bool, error) {
	switch strings.TrimSpace(val) {
	case "true":
		return true, nil
	case "false":
		return false, nil
	default:
		return false, fmt.Errorf("invalid boolean %q", val)
	}
}

func parseStringArray(val string) ([]string, error) {
	v := strings.TrimSpace(val)
	if len(v) < 2 || v[0] != '[' || v[len(v)-1] != ']' {
		return nil, fmt.Errorf("expected array, got %q", val)
	}
	body := strings.TrimSpace(v[1 : len(v)-1])
	if body == "" {
		return []string{}, nil
	}
	parts := strings.Split(body, ",")
	items := make([]string, 0, len(parts))
	for _, part := range parts {
		s, err := parseQuotedString(strings.TrimSpace(part))
		if err != nil {
			return nil, err
		}
		items = append(items, s)
	}
	return items, nil
}
