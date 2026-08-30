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
# Uncomment a line to change it. Reloading belongs to the throwntomd daemon:
# it watches this file and picks an edit up within a few seconds, the pomodoro
# already running included — shortening work_minutes below the time the
# current pomodoro has already spent ends it. The daemon reloads [pomodoro],
# [[schedule]], repeat_secs and repeat_limit_secs; the settings it does not
# reload say so under their own heading. Running throwntom by itself, without
# the daemon, reloads nothing at all: it reads this file once as it launches,
# so there every setting waits for the next launch.
# An empty file is read as a save still in flight and ignored, so emptying
# this one resets nothing: delete it instead and the daemon writes a fresh
# copy the next time it starts.
#
# Settings outside a section must stay above the first [pomodoro] header:
# TOML puts a bare key written after a section header inside that section, so
# repeat_secs moved down there becomes pomodoro.repeat_secs and is rejected
# as an unknown key.

# Seconds between the repeats of an unanswered reminder.
# repeat_secs = 20

# Seconds a reminder keeps repeating before it gives up.
# repeat_limit_secs = 300

# Command run to play a reminder sound, as a list of arguments: the first is
# the executable, the rest are its arguments. It is run as written; the sound
# name is not passed to it, so one command serves every sound and the morning
# nudge, the confirm reminder and the sound test cannot be told apart by ear.
# Leaving this empty keeps the platform's own sounds: the macOS system sounds,
# or on Linux paplay, canberra-gtk-play, aplay and finally the terminal bell.
# On Linux that same chain also backs up a command that fails, so a broken
# command there still makes a noise; on macOS it replaces the sound outright.
# This one belongs to the throwntom terminal interface: throwntomd plays no
# sound at all, so setting this changes nothing there, restart or not. The
# terminal interface builds its notifier from this as it launches, so a
# change waits for the next launch.
# macOS example: sound_command = ["afplay", "/System/Library/Sounds/Glass.aiff"]
# Linux example: sound_command = ["paplay", "/usr/share/sounds/freedesktop/stereo/complete.oga"]
# sound_command = []

# Whether the morning reminder is owed when the daemon starts during
# scheduled hours with nothing running. A reload does not apply this: it
# answers a question only start-up asks.
# morning_reminder_pending = true

# Whether the interface uses emoji. This one belongs to the throwntom
# terminal interface; the daemon has no use for it.
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
# above tier_mid is a full day, one above tier_low is moderate, and anything
# else is light. Both are strict, so with the defaults a day of 2 is light
# and a day of 5 is moderate. These belong to the throwntom terminal
# interface; the daemon has no use for them. Uncomment the [stats] header
# too.
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
	// Exclusive, not Write: the Stat above only rules out the common case. If
	// another process creates path in the window before this call, Write
	// would clobber its config; WriteExclusive leaves it alone instead.
	if err := atomicfile.WriteExclusive(path, []byte(Template), 0o644); err != nil {
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
