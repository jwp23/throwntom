package config

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/jwp23/throwntom/v3/internal/atomicfile"
)

// Template is the config file throwntom writes when none exists: every
// setting, documented, commented out and showing its default. Uncommenting a
// line and editing it is the whole workflow — the daemon picks the change up
// without a restart.
//
// Every commented setting must state the real default; template_test.go
// uncomments the file and checks it parses to exactly Default().
const Template = `# throwntom configuration.
#
# Every setting below is shown with its default and commented out.
# Uncomment a line to change it. The daemon watches this file and applies
# edits immediately, including to the pomodoro already running: shortening
# work_minutes below the time the current pomodoro has already spent ends it.

# Seconds between the repeats of an unanswered reminder.
# repeat_secs = 20

# Seconds a reminder keeps repeating before it gives up.
# repeat_limit_secs = 300

# Command run to play a reminder sound, as a list of arguments. Empty means
# no sound. The sound name is appended as the final argument.
# macOS example: sound_command = ["afplay", "/System/Library/Sounds/Glass.aiff"]
# Linux example: sound_command = ["paplay", "/usr/share/sounds/freedesktop/stereo/complete.oga"]
# sound_command = []

# Whether the morning reminder is owed when the daemon starts during
# scheduled hours with nothing running.
# morning_reminder_pending = true

# Whether the interface uses emoji.
# emoji = true

# [pomodoro] sets the length of each phase and how often a long break comes.
# Uncomment the [pomodoro] header too when you uncomment any key under it.
# [pomodoro]

# Minutes of focused work in one pomodoro.
# work_minutes = 25

# Minutes of the break after a pomodoro.
# short_break_minutes = 5

# Minutes of the longer break that ends a cycle.
# long_break_minutes = 15

# Pomodoros per cycle: the break after this many is the long one.
# long_break_every = 4

# [[schedule]] is when the morning reminder is due. Repeat the block for
# different times on different days. "days" accepts Sun, Mon, Tue, Wed, Thu,
# Fri, Sat and the aliases "weekday" and "weekend"; an alias covers only the
# days no other block names. "time" is 24-hour HH:MM. Uncomment the
# [[schedule]] header along with the keys under it.
# [[schedule]]
# days = ["Mon", "Tue", "Wed", "Thu", "Fri"]
# time = "09:15"

# [stats] sets the thresholds the daily counts are coloured against: a day
# below tier_low is light, below tier_mid is moderate, and at or above
# tier_mid is a full day. Uncomment the [stats] header too.
# [stats]
# tier_low = 2
# tier_mid = 5
`

// EnsureFile writes the documented template to path when nothing is there
// yet, so a first run leaves the user a config to edit rather than a missing
// file. An existing config is never touched.
func EnsureFile(path string) error {
	if _, err := os.Stat(path); err == nil {
		return nil
	} else if !os.IsNotExist(err) {
		return fmt.Errorf("stat config file %q: %w", path, err)
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return fmt.Errorf("create config directory: %w", err)
	}
	if err := atomicfile.Write(path, []byte(Template), 0o644); err != nil {
		return fmt.Errorf("write default config %q: %w", path, err)
	}
	return nil
}

// ResolvePath names the config file a caller means: path when it gives one,
// and the file in the user's throwntom directory otherwise.
func ResolvePath(path string) (string, error) {
	if path != "" {
		return path, nil
	}
	return DirPath("config.toml")
}
