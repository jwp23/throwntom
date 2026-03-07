package config

import (
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"

	"github.com/BurntSushi/toml"
)

var timePattern = regexp.MustCompile(`^[0-9]{2}:[0-9]{2}$`)

type Config struct {
	Pomodoro struct {
		WorkMinutes       int `toml:"work_minutes"`
		ShortBreakMinutes int `toml:"short_break_minutes"`
		LongBreakMinutes  int `toml:"long_break_minutes"`
		LongBreakEvery    int `toml:"long_break_every"`
	} `toml:"pomodoro"`
	Schedule struct {
		Days []string `toml:"days"`
		Time string   `toml:"time"`
	} `toml:"schedule"`
	RepeatSecs             int      `toml:"repeat_secs"`
	SoundCommand           []string `toml:"sound_command"`
	MorningReminderPending bool     `toml:"morning_reminder_pending"`
	Emoji                  bool     `toml:"emoji"`
}

func Default() Config {
	var cfg Config
	cfg.Schedule.Days = []string{"Mon", "Tue", "Wed", "Thu", "Fri"}
	cfg.Schedule.Time = "09:15"
	cfg.Pomodoro.WorkMinutes = 25
	cfg.Pomodoro.ShortBreakMinutes = 5
	cfg.Pomodoro.LongBreakMinutes = 15
	cfg.Pomodoro.LongBreakEvery = 4
	cfg.RepeatSecs = 20
	cfg.MorningReminderPending = true
	cfg.Emoji = true
	return cfg
}

func LoadBytes(b []byte) (Config, error) {
	cfg := Default()
	md, err := toml.Decode(string(b), &cfg)
	if err != nil {
		return Config{}, fmt.Errorf("parse config: %w", err)
	}
	if undecoded := md.Undecoded(); len(undecoded) > 0 {
		return Config{}, fmt.Errorf("unknown key %q", undecoded[0])
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
	if cfg.Pomodoro.WorkMinutes <= 0 {
		return fmt.Errorf("work_minutes must be > 0")
	}
	if cfg.Pomodoro.ShortBreakMinutes <= 0 {
		return fmt.Errorf("short_break_minutes must be > 0")
	}
	if cfg.Pomodoro.LongBreakMinutes <= 0 {
		return fmt.Errorf("long_break_minutes must be > 0")
	}
	if cfg.Pomodoro.LongBreakEvery <= 0 {
		return fmt.Errorf("long_break_every must be > 0")
	}
	if cfg.RepeatSecs <= 0 {
		return fmt.Errorf("repeat_secs must be > 0")
	}
	if len(cfg.Schedule.Days) == 0 {
		return fmt.Errorf("schedule_days must contain at least one day")
	}
	if err := validateSoundCommand(cfg.SoundCommand); err != nil {
		return err
	}
	return validateScheduleDays(cfg.Schedule.Days)
}

func validateSoundCommand(parts []string) error {
	for i, part := range parts {
		if strings.TrimSpace(part) == "" {
			return fmt.Errorf("sound_command[%d] must be a non-empty string", i)
		}
	}
	return nil
}

func validateScheduleDays(days []string) error {
	for _, day := range days {
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
