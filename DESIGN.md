---
version: alpha
name: Throwntom
description: Visual identity of the throwntom pomodoro timer — terminal UI, macOS window app, and app icon.
omitted:
  - section: typography
    reason: "The TUI renders in whatever font the terminal uses; the macOS app uses SwiftUI's system text styles (.largeTitle, .title2, .body, .caption) with no explicit sizes or families in code."
colors:
  primary: "#F68C31"
  icon-orange: "#F46B25"
  icon-orange-light: "#F68C31"
  icon-tomato: "#DC2B24"
  icon-tomato-shade: "#C83A33"
  icon-outline: "#48120F"
  icon-leaf: "#4B6C2D"
  icon-leaf-light: "#709534"
  icon-highlight: "#FDC19C"
  work-light: "#B94A0E"
  work-dark: "#F68C31"
  short-break-light: "#0E6F73"
  short-break-dark: "#3FC1C9"
  long-break-light: "#1F4E9C"
  long-break-dark: "#7AA6F5"
  idle-light: "#6B5E00"
  idle-dark: "#E6C84A"
  paused-light: "#6B6B6B"
  paused-dark: "#9A9A9A"
  awaiting-confirm-light: "#A8330F"
  awaiting-confirm-dark: "#FF7A59"
  error-light: "#B3001B"
  error-dark: "#FF5C5C"
  macos-ink: "#1F130C"
  macos-cream: "#FFF6EA"
  macos-outline: "#2B1A10"
  macos-work: "#D9651A"
  macos-work-chip: "#622D0C"
  macos-short-break: "#1E9AA3"
  macos-short-break-chip: "#0D4549"
  macos-long-break: "#5A8CE0"
  macos-long-break-chip: "#283F65"
  macos-idle: "#B8961F"
  macos-idle-chip: "#53440E"
  macos-paused: "#8A8A8E"
  macos-paused-chip: "#3E3E40"
  macos-awaiting-confirm: "#E8583A"
  macos-awaiting-confirm-chip: "#68281A"
  macos-disconnected: "#3A2A22"
  macos-disconnected-chip: "#FFF6EA"
  macos-work-panel: "#9C4913"
  macos-short-break-panel: "#166F75"
  macos-long-break-panel: "#4165A1"
  macos-idle-panel: "#846C16"
  macos-paused-panel: "#636366"
  macos-awaiting-confirm-panel: "#A73F2A"
  macos-disconnected-panel: "#2A1E18"
spacing:
  row: 2px
  stack: 8px
  window-padding: 16px
  window-min-width: 320px
  slot-size: 72px
  chip-radius: 6px
  slot-radius: 10px
  panel-radius: 8px
components:
  status-line-work:
    textColor: "{colors.work-dark}"
  status-line-short-break:
    textColor: "{colors.short-break-dark}"
  status-line-long-break:
    textColor: "{colors.long-break-dark}"
  status-line-idle:
    textColor: "{colors.idle-dark}"
  status-line-paused:
    textColor: "{colors.paused-dark}"
  status-line-awaiting-confirm:
    textColor: "{colors.awaiting-confirm-dark}"
  message-error:
    textColor: "{colors.error-dark}"
  status-line-work-light:
    textColor: "{colors.work-light}"
  status-line-short-break-light:
    textColor: "{colors.short-break-light}"
  status-line-long-break-light:
    textColor: "{colors.long-break-light}"
  status-line-idle-light:
    textColor: "{colors.idle-light}"
  status-line-paused-light:
    textColor: "{colors.paused-light}"
  status-line-awaiting-confirm-light:
    textColor: "{colors.awaiting-confirm-light}"
  message-error-light:
    textColor: "{colors.error-light}"
  stat-tier-high:
    textColor: "{colors.short-break-dark}"
  stat-tier-mid:
    textColor: "{colors.awaiting-confirm-dark}"
  stat-tier-low:
    textColor: "{colors.paused-dark}"
  app-icon:
    backgroundColor: "{colors.icon-orange}"
    textColor: "{colors.icon-outline}"
  window-work:
    backgroundColor: "{colors.macos-work}"
    textColor: "{colors.macos-ink}"
  window-short-break:
    backgroundColor: "{colors.macos-short-break}"
    textColor: "{colors.macos-ink}"
  window-long-break:
    backgroundColor: "{colors.macos-long-break}"
    textColor: "{colors.macos-ink}"
  window-idle:
    backgroundColor: "{colors.macos-idle}"
    textColor: "{colors.macos-ink}"
  window-paused:
    backgroundColor: "{colors.macos-paused}"
    textColor: "{colors.macos-ink}"
  window-awaiting-confirm:
    backgroundColor: "{colors.macos-awaiting-confirm}"
    textColor: "{colors.macos-ink}"
  window-disconnected:
    backgroundColor: "{colors.macos-disconnected}"
    textColor: "{colors.macos-cream}"
  chip-primary:
    backgroundColor: "{colors.macos-outline}"
    textColor: "{colors.macos-cream}"
    rounded: "{spacing.chip-radius}"
  chip-secondary-work:
    backgroundColor: "{colors.macos-work-chip}"
  chip-secondary-short-break:
    backgroundColor: "{colors.macos-short-break-chip}"
  chip-secondary-long-break:
    backgroundColor: "{colors.macos-long-break-chip}"
  chip-secondary-idle:
    backgroundColor: "{colors.macos-idle-chip}"
  chip-secondary-paused:
    backgroundColor: "{colors.macos-paused-chip}"
  chip-secondary-awaiting-confirm:
    backgroundColor: "{colors.macos-awaiting-confirm-chip}"
  chip-secondary-disconnected:
    backgroundColor: "{colors.macos-disconnected-chip}"
  panel-work:
    backgroundColor: "{colors.macos-work-panel}"
    textColor: "{colors.macos-cream}"
  panel-short-break:
    backgroundColor: "{colors.macos-short-break-panel}"
    textColor: "{colors.macos-cream}"
  panel-long-break:
    backgroundColor: "{colors.macos-long-break-panel}"
    textColor: "{colors.macos-cream}"
  panel-idle:
    backgroundColor: "{colors.macos-idle-panel}"
    textColor: "{colors.macos-cream}"
  panel-paused:
    backgroundColor: "{colors.macos-paused-panel}"
    textColor: "{colors.macos-cream}"
  panel-awaiting-confirm:
    backgroundColor: "{colors.macos-awaiting-confirm-panel}"
    textColor: "{colors.macos-cream}"
  panel-disconnected:
    backgroundColor: "{colors.macos-disconnected-panel}"
    textColor: "{colors.macos-cream}"
  mascot-slot:
    backgroundColor: "{colors.macos-cream}"
    width: "{spacing.slot-size}"
    rounded: "{spacing.slot-radius}"
  window:
    padding: "{spacing.window-padding}"
    width: "{spacing.window-min-width}"
---

# Throwntom Design

## Overview

Throwntom looks like a sticker slapped on a laptop lid: the app icon
(`macos/bundle/icon/throwntom-icon-1024-masked.png`) is a grinning cartoon tomato with a
green stem and one leaf, thick dark outlines, and a highlight glint, sitting on a flat
orange-to-red-orange squircle. The README badge (`docs/images/throwntom.png`) is the same
tomato flying across a cream circular sticker with motion streaks, juice drops, and a clock,
with the word "throwntom" in rounded bubble lettering. The register is Duolingo's owl, not
Apple's Clock — friendly, a little goofy, and unbothered by being a productivity tool.

Everything the user actually operates is far plainer than the icon. The TUI is a
frame of a few lines — status, secondary hint, message, the `>` prompt — that only uses
foreground colour and an optional emoji, never boxes or backgrounds. The macOS client is one window whose whole ground is the colour of the current phase — a jewel version of the TUI state colour — with a cream mascot slot beside the phase name, today's pomodoros drawn as a row of tomatoes, and the timer verbs as chips. The TUI stays a few bare lines; the window is where the tomato's personality lives on screen.

## Colors

All colours live in `cmd/throwntom/theme.go` as `lipgloss.AdaptiveColor` pairs: a darker
value for light terminals and a brighter one for dark terminals. Every pair meets WCAG AA
(4.5:1) on white and on black — `TestPaletteMeetsAAContrastInBothModes` enforces it — and
rest states sit on teal and blue rather than green so that rest, attention, and error never
share the red–green axis. Each colour means one timer state. In the TUI, colour is applied to the status line text only; the frame never
paints a background, a border, or a second colour on the same line except for the coloured
"Next: …" stage name inside a plain sentence. `primary` is the brand orange: the icon's
lighter squircle orange, also the dark-terminal work value. The `icon-*` tokens are the
dominant colours of the app icon as measured by `tools/icon-colors.sh`; they belong to the
icon and README badge, never to the TUI or the macOS client. The linter reports the
`icon-*` tokens the `app-icon` component does not reference as orphaned; that is
intentional — they are reference swatches for redrawing the icon, not inputs to any UI
component. Component tokens without a suffix
are the dark-terminal variants; `-light` variants carry the light-terminal values.

- **Work (#B94A0E light / #F68C31 dark):** The icon's orange, darkened for light terminals.
  The brand colour and the colour of a running pomodoro. Use it only for the status line while in
  `Work`; it must not be used for hints, prompts, or decoration, or it stops meaning "you
  are on the clock".
- **Short break (#0E6F73 / #3FC1C9):** Teal. Rest. Never used for success messages — the
  TUI has no success colour; plain text is the default.
- **Long break (#1F4E9C / #7AA6F5):** Blue, a deeper rest than teal, and separable from it
  for deuteranopes. Do not swap either break colour for a green.
- **Idle (#6B5E00 / #E6C84A):** Olive / straw yellow. The timer is ready but nothing is
  running. This is also the default for any unknown state.
- **Paused (#6B6B6B / #9A9A9A):** Grey. The only muted colour; also reused for the lowest
  stats tier. Nothing else is dimmed.
- **Awaiting confirm (#A8330F / #FF7A59):** The tomato's red-orange. A stage has ended and
  the next one waits for `enter`. Deliberately close to work orange — same activity, one
  keypress away — so the `!`/🔔 glyph, not the hue, carries the distinction. Also the mid
  stats tier.
- **Error (#B3001B / #FF5C5C):** Red, for the message line only when `IsError` is set. It
  never colours the status line; a timer state is never "red".

**macOS grounds.** `macos-work`, `macos-short-break`, `macos-long-break`, `macos-idle`, `macos-paused` and `macos-awaiting-confirm` are mid-tone, saturated versions of the same six hues and fill the entire window; `macos-disconnected` is a dark brown used while the daemon is unreachable. All text on a ground is `macos-ink` (cream on disconnected). `macos-cream` is the mascot slot and the label of the primary chip; `macos-outline`, the icon's outline brown, is the primary chip. Each `*-chip` token is its ground under 55% black and carries white text, except `macos-disconnected-chip`, which is cream because that ground shows no chips. `PaletteTests` asserts text on ground and label on chip at 4.5:1 and chip on ground at 3:1; `DesignTokensTests` asserts these values equal `Palette.swift`. The look is the same in light and dark system appearance.

The dashboard (`cmd/throwntom/stats_handler.go`) reuses three of these for pomodoro counts:
teal above `tier_mid` (default 5), tomato above `tier_low` (default 2), grey otherwise —
each paired with a glyph (● / ◐ / ○) so the tier reads without colour. The macOS client's task rows use `macos-ink` for text and the system yellow star for focus.

## Typography

Omitted (see front matter). Two things are still fixed in code and worth knowing:

- The TUI's only "type styles" are foreground colour; there is no bold, italic, or underline
  anywhere in `theme.go`.
- The macOS window uses `.largeTitle` bold for the phase name, `.title2` with monospaced digits for the countdown, `.body` for the next-stage line and tasks, `.caption` for the garden summary, section labels, notes and chip shortcut hints (the hints monospaced). Notes are sentences that say what to do, so they wrap rather than truncate.

## Layout

The TUI frame (`renderThemedFrame`) is a stack of lines in a fixed order: status; the
secondary hint (or the morning-reminder hint) when there is one; the message, one line per
newline in it; the prompt. Every line is clamped to terminal width minus one by
`clampANSILine`, with a `...` ellipsis when at least four columns are available and a hard
cut otherwise; nothing wraps, nothing is centred, there are no margins. The status line is `<icon> <coloured text>`, with a single space between.

The macOS window is one vertical stack with 16pt padding: timer header (72pt slot, phase name, countdown), tomato garden, count line, chips, reminder banner and errors, focus list, then an optional tasks or stats panel. Panels expand the window downward; the minimum width is 320pt.

## Elevation & Depth

Flat. The TUI has no depth at all; hierarchy is carried by line order and by colour on the
first line only. The macOS client inherits the system window chrome; panels are the `*-panel` tokens, the ground darkened by 28%, with cream text, an 8pt radius, chips 6pt, the slot 10pt. Nothing casts a shadow.

## Shapes

Omitted (see front matter). The icon is delivered as a 1024px PNG already masked to the
macOS squircle, plus an unmasked square; the `.icns` is built from the masked one.

## Components

### Status line (TUI)

`<icon> <state text>`, coloured by state. The icon is one of two sets, chosen by the
`emoji` config flag:

| State | Emoji | ASCII |
|---|---|---|
| Work | 🍅 | `*` |
| Short / long break | ☕ / 🌿 | `~` |
| Idle | 🌱 | `-` |
| Paused | ⏸️ | `\|\|` |
| Awaiting confirm | 🔔 | `!` |
| Morning reminder pending (appended) | 🔔 | `[!]` |

The ASCII set must stay short plain ASCII — one or two characters for a state, three for
the bracketed reminder marker — so the frame never depends on terminal font coverage. The emoji set is the icon's personality leaking into the terminal
and is the only place the product uses emoji.

### Next-stage line

`Next: <stage (N min)> — press enter to start, or snooze 10m to hold your place`, where
only the stage phrase is coloured, in the colour of the *next* state.

### Message line

Plain text, or error red when the message is an error. Multi-line messages are split and
each line clamped.

### Prompt

`>`, one space, then the input. Never styled.

### Stats tiers

`<glyph> <count>`: `● 7` in teal above `tier_mid`, `◐ 3` in tomato above `tier_low`,
`○ 1` in grey otherwise. The glyph and the colour always change together.

### Task row (macOS)

`star.fill` in system yellow when focused, otherwise a `circle` in the panel's inherited
text colour; description in that same inherited colour, struck through (never dimmed) when
done.

### Mascot slot (macOS)

A `macos-cream` rounded square, 72pt, with a 1.5pt `macos-outline` inset stroke, holding the phase glyph: 🍅 work, ☕ short break, 🌿 long break, 🌱 idle, 🔔 awaiting confirm, and SF Symbol `pause.fill` in `macos-outline` when paused. Reserved for the mascot.

### Chip (macOS)

`<title>  <shortcut>`: the primary verb on `macos-outline` in `macos-cream`; every other verb on the phase's `*-chip` colour in white. The shortcut is monospaced caption text at 75% opacity.

### Tomato garden (macOS)

🍅 per completed pomodoro, grouped into blocks of `long_break_every` with a gap between blocks, blocks wrapped to the window width; the unfilled slots of the current block are the same glyph at 35% opacity. Beneath it, `N today · M blocks done`.

## Do's and Don'ts

- Do keep one colour per line in the TUI, and only on the status line and the error message.
- Don't add a bold, background, border, or box to the TUI frame; it is deliberately a few
  bare lines that clamp rather than wrap.
- Do reuse the state colours by meaning (grey = low/inactive, tomato = attention, teal/blue =
  rest) rather than adding new hues, and keep every pair above 4.5:1 on both white and black.
- Don't let a meaning rest on colour alone; pair it with a glyph, as the states and tiers do.
- Don't colour the prompt or secondary hint, and never render a timer state in red.
- Do keep the ASCII icon set to plain ASCII; add any new state to both the emoji and ASCII
  tables at once.
- Do keep the macOS palette in `Palette.swift` and these tokens in step; a new ground needs a `*-chip` partner and must pass `PaletteTests`. Don't add fonts; the system text styles are the only type.
- Do keep the light/dark pairs in `theme.go` together; a new colour needs both values.
