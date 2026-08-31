package core

import (
	"encoding/json"
	"reflect"
	"regexp"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/doctest"
	"github.com/jwp23/throwntom/v3/internal/notifier"
	"github.com/jwp23/throwntom/v3/internal/reminder"
)

// The README and the config template both promise a reader which settings the
// daemon puts in force without a restart. That promise is a claim about
// ApplyConfig, so it is checked against ApplyConfig here rather than left to
// whoever last edited the prose.

// reloadedSettings is the set this file proves ApplyConfig applies, named the
// way the docs name it. The docs must promise exactly this set.
var reloadedSettings = []string{
	"[pomodoro]",
	"[[schedule]]",
	"repeat_secs",
	"repeat_limit_secs",
	"float_window_when_waiting",
}

// restartSettings is every other setting a user can write in config.toml. A
// reload does not apply these, and the docs must list exactly these under the
// restart heading.
var restartSettings = []string{
	"sound_command",
	"morning_reminder_pending",
	"emoji",
	"[stats]",
}

// backticked matches the README's markup for a setting's name.
var backticked = regexp.MustCompile("`([^`]+)`")

// documentedRestartList reads the settings the README lists as needing a
// restart: the bullets under the sentence introducing them, each naming its
// settings ahead of the dash that starts the explanation.
func documentedRestartList(t *testing.T, readme string) []string {
	t.Helper()
	start := strings.Index(readme, "The rest needs a restart")
	if start < 0 {
		t.Fatal("README no longer introduces the settings that need a restart")
	}
	var names []string
	started := false
	for _, line := range strings.Split(readme[start:], "\n") {
		if !strings.HasPrefix(line, "- ") {
			// The list ends at the blank line after it; the indented
			// continuations of a bullet carry no setting name.
			if started && strings.TrimSpace(line) == "" {
				break
			}
			continue
		}
		started = true
		head, _, found := strings.Cut(line, "—")
		if !found {
			t.Fatalf("restart bullet %q does not name its settings before a dash", line)
		}
		for _, m := range backticked.FindAllStringSubmatch(head, -1) {
			names = append(names, m[1])
		}
	}
	if !started {
		t.Fatal("README lists no settings under the restart heading")
	}
	sort.Strings(names)
	return names
}

// TestReadmeListsTheSettingsThatNeedARestart is the other half of the reload
// contract. Without it a setting could be dropped from the restart list, or
// gain one, with nothing to notice — the drift this file exists to stop.
func TestReadmeListsTheSettingsThatNeedARestart(t *testing.T) {
	readme, err := doctest.Read("README.md")
	if err != nil {
		t.Fatalf("read README: %v", err)
	}
	got := documentedRestartList(t, readme)
	if want := sorted(restartSettings); !reflect.DeepEqual(got, want) {
		t.Errorf("README says %v need a restart, want %v", got, want)
	}
}

// TestReadmeGivesTheReasonEachRestartSettingIsNotReloaded pins the sentence
// under each bullet, not only the name. A bullet that keeps its name and
// gains a false explanation is the failure this branch exists to catch, and
// the sound_command line is the one CLAUDE.md holds up as the example.
func TestReadmeGivesTheReasonEachRestartSettingIsNotReloaded(t *testing.T) {
	readme, err := doctest.Read("README.md")
	if err != nil {
		t.Fatalf("read README: %v", err)
	}
	prose := doctest.Unwrap(readme)
	for _, want := range []string{
		"the terminal UI that does use it builds its notifier once, at startup; neither rereads it",
		"it answers whether today's morning reminder is owed when the daemon starts",
		"client settings, read by `throwntom` when it launches",
	} {
		if !strings.Contains(prose, want) {
			t.Errorf("README no longer explains a restart-only setting with %q", want)
		}
	}
}

// TestAReloadDoesNotRebuildTheNotifier pins the mechanism the README gives
// for sound_command: a notifier is built once, at start-up, and a reload does
// not reread the setting. Without this the bullet could keep its name in the
// restart list while a reload quietly began applying it.
func TestAReloadDoesNotRebuildTheNotifier(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	cfg.SoundCommand = []string{"first"}
	built := noopNotifier{}
	c := newCore(cfg, built)
	defer c.Stop()

	cfg.SoundCommand = []string{"second"}
	c.ApplyConfig(cfg)

	c.mu.Lock()
	defer c.mu.Unlock()
	if c.notifier != notifier.Notifier(built) {
		t.Fatal("a reload replaced the notifier, which the README says is built once at start-up")
	}
}

// TestTheDaemonCarriesNoClientSetting pins "client settings" for emoji and
// the [stats] tiers: the daemon publishes neither, which is why a reload
// could not deliver them to the terminal interface even in principle.
func TestTheDaemonCarriesNoClientSetting(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	cfg.Emoji = true
	cfg.Stats.TierLow = 3
	cfg.Stats.TierMid = 8
	c := newCore(cfg, noopNotifier{})
	defer c.Stop()

	published, err := json.Marshal(c.State())
	if err != nil {
		t.Fatalf("marshal state: %v", err)
	}
	for _, key := range []string{"emoji", "tier_low", "tier_mid"} {
		if strings.Contains(string(published), key) {
			t.Errorf("the daemon publishes %q, which the README calls a client setting", key)
		}
	}
}

// reloadSentence matches the docs' promise in either wording: the template
// says "The daemon reloads …" and the README "Reloading covers …". Both end
// the list at the first sentence break.
var reloadSentence = regexp.MustCompile(`(?:daemon reloads|Reloading covers) ([^.;]+)`)

// documentedReloadList reads the list of settings a document promises are
// reloaded. Backticks are the README's markup, not part of a setting's name.
func documentedReloadList(t *testing.T, doc, source string) []string {
	t.Helper()
	m := reloadSentence.FindStringSubmatch(strings.ReplaceAll(unwrapFor(source, doc), "`", ""))
	if m == nil {
		t.Fatalf("%s no longer states which settings the daemon reloads", source)
	}
	var names []string
	for _, part := range strings.Split(strings.ReplaceAll(m[1], " and ", ", "), ",") {
		if name := strings.TrimSpace(part); name != "" {
			names = append(names, name)
		}
	}
	sort.Strings(names)
	return names
}

// unwrapFor joins a document's wrapped prose, dropping comment markers only
// for the config template, whose prose is commented out.
func unwrapFor(source, text string) string {
	if strings.Contains(source, "template") {
		return doctest.UnwrapComments(text)
	}
	return doctest.Unwrap(text)
}

func sorted(names []string) []string {
	out := append([]string(nil), names...)
	sort.Strings(out)
	return out
}

// TestDocsPromiseTheSettingsApplyConfigReloads holds the README and the
// template to the same list, and both to the list this file proves below.
func TestDocsPromiseTheSettingsApplyConfigReloads(t *testing.T) {
	readme, err := doctest.Read("README.md")
	if err != nil {
		t.Fatalf("read README: %v", err)
	}
	want := sorted(reloadedSettings)
	for _, doc := range []struct{ source, text string }{
		{"README.md", readme},
		{"the config template", config.Template},
	} {
		if got := documentedReloadList(t, doc.text, doc.source); !reflect.DeepEqual(got, want) {
			t.Errorf("%s promises %v is reloaded, ApplyConfig reloads %v", doc.source, got, want)
		}
	}
}

// TestDocsClassifyEverySetting fails when a setting is added to config.Config
// without the docs saying whether a reload applies it — the question a reader
// asks first and the one nothing else answers.
func TestDocsClassifyEverySetting(t *testing.T) {
	classified := map[string]bool{}
	for _, name := range append(append([]string(nil), reloadedSettings...), restartSettings...) {
		classified[name] = true
	}
	for _, name := range settingNames(reflect.TypeOf(config.Config{})) {
		if !classified[name] {
			t.Errorf("config setting %q is documented as neither reloaded nor needing a restart", name)
		}
	}
}

// settingNames lists a config struct's settings by the name a user writes in
// config.toml: a section by its header, everything else by its key.
func settingNames(t reflect.Type) []string {
	var names []string
	for i := range t.NumField() {
		field := t.Field(i)
		tag := field.Tag.Get("toml")
		if tag == "" {
			continue
		}
		switch field.Type.Kind() {
		case reflect.Struct:
			names = append(names, "["+tag+"]")
		case reflect.Slice:
			if field.Type.Elem().Kind() == reflect.Struct {
				names = append(names, "[["+tag+"]]")
				continue
			}
			names = append(names, tag)
		default:
			names = append(names, tag)
		}
	}
	return names
}

// TestEverySettingDocumentedAsReloadedIsApplied is the other half: the list
// the docs promise is worth nothing unless each name on it reaches the
// running core. Each case changes one setting and looks for its effect.
func TestEverySettingDocumentedAsReloadedIsApplied(t *testing.T) {
	// 07:00 on a Sunday is after 06:30 on every day and before the
	// weekday-only 09:15 the default schedule uses.
	sunday := time.Date(2026, 8, 30, 7, 0, 0, 0, time.UTC)

	applied := map[string]func(t *testing.T, c *Core, cfg *config.Config){
		"[pomodoro]": func(t *testing.T, c *Core, cfg *config.Config) {
			c.execute(cmdStart)
			cfg.Pomodoro.WorkMinutes = 50
			c.ApplyConfig(*cfg)
			if remaining := time.Until(*c.State().PhaseEndAt); remaining < 40*time.Minute {
				t.Fatalf("the running phase kept its old duration: %s left", remaining)
			}
		},
		"[[schedule]]": func(t *testing.T, c *Core, cfg *config.Config) {
			cfg.Schedule = []config.ScheduleEntry{{
				Days: []string{"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"},
				Time: "06:30",
			}}
			c.ApplyConfig(*cfg)
			c.mu.Lock()
			defer c.mu.Unlock()
			if !c.scheduler.IsActiveNow(sunday) {
				t.Fatal("the reloaded schedule did not reach the scheduler")
			}
		},
		"repeat_secs": func(t *testing.T, c *Core, cfg *config.Config) {
			cfg.RepeatSecs = 45
			c.ApplyConfig(*cfg)
			assertPolicy(t, c, reminder.NewPolicy(45*time.Second, time.Duration(cfg.RepeatLimitSecs)*time.Second))
		},
		"repeat_limit_secs": func(t *testing.T, c *Core, cfg *config.Config) {
			cfg.RepeatLimitSecs = 600
			c.ApplyConfig(*cfg)
			assertPolicy(t, c, reminder.NewPolicy(time.Duration(cfg.RepeatSecs)*time.Second, 600*time.Second))
		},
		"float_window_when_waiting": func(t *testing.T, c *Core, cfg *config.Config) {
			cfg.FloatWindowWhenWaiting = true
			c.ApplyConfig(*cfg)
			if !c.State().FloatWindowWhenWaiting {
				t.Fatal("the reloaded setting did not reach the published state")
			}
		},
	}

	for _, name := range reloadedSettings {
		check, ok := applied[name]
		if !ok {
			t.Fatalf("no case proves %q is reloaded", name)
		}
		t.Run(name, func(t *testing.T) {
			cfg := config.Default()
			cfg.MorningReminderPending = false
			c := newCore(cfg, noopNotifier{})
			defer c.Stop()
			check(t, c, &cfg)
		})
	}
}

func assertPolicy(t *testing.T, c *Core, want reminder.Policy) {
	t.Helper()
	c.reminder.mu.Lock()
	got := c.reminder.policy
	c.reminder.mu.Unlock()
	if got != want {
		t.Fatalf("reminder policy is %+v, want %+v", got, want)
	}
}

// TestDocsSayTheDaemonPublishesFloatWindowWhenWaiting guards the one setting
// the daemon carries without acting on. Saying only that the daemon does
// nothing with it contradicts the same document's reload list and hides the
// reason it is reloaded at all: the state it publishes is where the macOS app
// reads it.
func TestDocsSayTheDaemonPublishesFloatWindowWhenWaiting(t *testing.T) {
	readme, err := doctest.Read("README.md")
	if err != nil {
		t.Fatalf("read README: %v", err)
	}
	for _, doc := range []struct{ source, text, want string }{
		{"README.md", readme, "it reloads this setting and publishes it in its state for the macOS app to read"},
		{"the config template", config.Template, "it reloads this setting and publishes it in its state for the app to read"},
	} {
		if !strings.Contains(unwrapFor(doc.source, doc.text), doc.want) {
			t.Errorf("%s does not say the daemon publishes float_window_when_waiting; it says only that the daemon does not act on it", doc.source)
		}
	}

	cfg := config.Default()
	cfg.MorningReminderPending = false
	cfg.FloatWindowWhenWaiting = true
	c := newCore(cfg, noopNotifier{})
	defer c.Stop()

	if !c.State().FloatWindowWhenWaiting {
		t.Fatal("the daemon's published state does not carry float_window_when_waiting")
	}
}

// TestDocsSayMorningReminderPendingNeedsARestart pairs the one restart-only
// setting the core holds with the behaviour: a reload must leave it alone,
// because start-up has already answered the question it asks.
func TestDocsSayMorningReminderPendingNeedsARestart(t *testing.T) {
	readme, err := doctest.Read("README.md")
	if err != nil {
		t.Fatalf("read README: %v", err)
	}
	for _, doc := range []struct{ source, text, want string }{
		{"README.md", readme, "a question already settled by the time an edit arrives"},
		{"the config template", config.Template, "A reload does not apply this"},
	} {
		if !strings.Contains(unwrapFor(doc.source, doc.text), doc.want) {
			t.Errorf("%s no longer says a reload leaves morning_reminder_pending alone", doc.source)
		}
	}

	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	defer c.Stop()

	cfg.MorningReminderPending = true
	c.ApplyConfig(cfg)

	c.mu.Lock()
	defer c.mu.Unlock()
	if c.morningPending {
		t.Fatal("a reload applied morning_reminder_pending, which the docs say needs a restart")
	}
}
