---
version: alpha
name: Throwntom
description: Visual identity of the throwntom pomodoro timer — terminal UI, macOS menu bar app, and app icon.
omitted:
  - section: typography
    reason: "The TUI renders in whatever font the terminal uses; the macOS app uses SwiftUI's system text styles (.headline, .caption) with no explicit sizes or families in code."
  - section: rounded
    reason: "No corner radii are set anywhere in code. Terminal cells have none; the macOS app inherits the system popover, window, and squircle icon mask."
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
spacing:
  row: 2px
  stack: 8px
  popover-padding: 12px
  popover-width: 280px
  task-window-min-width: 360px
  task-window-min-height: 240px
  task-window-width: 420px
  task-window-height: 360px
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
  popover:
    padding: "{spacing.popover-padding}"
    width: "{spacing.popover-width}"
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
four-line frame — status line, secondary hint, message, `> ` prompt — that only uses
foreground colour and an optional emoji, never boxes or backgrounds. The macOS client is a
stock `MenuBarExtra` popover and a plain `Window` that lean entirely on system controls.
The tomato supplies the personality; the interfaces stay out of the way. The one place the
icon's palette shows up in the running product is the work-state orange, which is the same
hue as the icon's background.

## Colors

All colours live in `cmd/throwntom/theme.go` as `lipgloss.AdaptiveColor` pairs: a darker
value for light terminals and a brighter one for dark terminals. Every pair meets WCAG AA
(4.5:1) on white and on black — `TestPaletteMeetsAAContrastInBothModes` enforces it — and
rest states sit on teal and blue rather than green so that rest, attention, and error never
share the red–green axis. Each colour means one timer state. Colour is applied to the status line text only; the frame never
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

The dashboard (`cmd/throwntom/stats_handler.go`) reuses three of these for pomodoro counts:
teal above `tier_mid` (default 5), tomato above `tier_low` (default 2), grey otherwise —
each paired with a glyph (● / ◐ / ○) so the tier reads without colour. The macOS client defines no colours of its own: `TaskRow` uses the system `.yellow`
for the focused star and `.secondary`/`.primary` for text, and the popover uses `.secondary`
for captions.

## Typography

Omitted (see front matter). Two things are still fixed in code and worth knowing:

- The TUI's only "type styles" are foreground colour; there is no bold, italic, or underline
  anywhere in `theme.go`.
- The macOS popover uses `.headline` for the status line, body text for actions and tasks,
  and `.caption` + `.secondary` for the connection/login-item note and for error and
  permission captions (`PopoverCaption`), which are allowed to wrap rather than truncate
  because the caption is a sentence that says what to do.

## Layout

The TUI frame is fixed at four lines in this order: status, secondary hint (or the
morning-reminder hint), message, prompt. Every line is clamped to terminal width minus one
with a `...` ellipsis (`clampANSILine`); nothing wraps, nothing is centred, there are no
margins. The status line is `<icon> <coloured text>`, with a single space between.

The macOS popover (`PopoverView.swift`) is a 280pt-wide vertical stack with 12pt padding and
8pt between items, separated into groups by `Divider()`: status → next stage → focus list →
timer actions | errors/permissions | Open Tasks | login item | quit. Focus items sit in a
tighter 2pt stack under a caption. Task rows have 2pt vertical padding. The task window
opens at 420×360 and cannot shrink below 360×240.

## Elevation & Depth

Flat. The TUI has no depth at all; hierarchy is carried by line order and by colour on the
first line only. The macOS client inherits the system popover shadow and window chrome and
adds none. The only shading in the whole product is on the icon: a soft gradient on the
squircle, a highlight on the tomato, and a slightly darker ring around the sticker in the
README badge.

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

The ASCII set must stay one or two plain ASCII characters so the frame never depends on
terminal font coverage. The emoji set is the icon's personality leaking into the terminal
and is the only place the product uses emoji.

### Next-stage line

`Next: <stage (N min)> — press enter to start, or snooze 10m to hold your place`, where
only the stage phrase is coloured, in the colour of the *next* state.

### Message line

Plain text, or error red when the message is an error. Multi-line messages are split and
each line clamped.

### Prompt

`> ` followed by the input. Never styled.

### Stats tiers

`<glyph> <count>`: `● 7` in teal above `tier_mid`, `◐ 3` in tomato above `tier_low`,
`○ 1` in grey otherwise. The glyph and the colour always change together.

### Task row (macOS)

`star.fill` in system yellow when focused, otherwise a `circle` in `.secondary`;
description in `.primary`, or struck through and `.secondary` when done. Empty task list is
a `ContentUnavailableView` with the `bolt.horizontal.circle` symbol.

### Menu bar item

Plain text label from `ConnectionStatus.text`: "Throwntom" when connected and idle, the
ticking countdown while running, "Starting timer…" or "Throwntom…" while connecting, with
" (reconnecting)" appended when the socket drops. No icon in the menu bar.

## Do's and Don'ts

- Do keep one colour per line in the TUI, and only on the status line and the error message.
- Don't add a bold, background, border, or box to the TUI frame; it is deliberately four
  bare lines that clamp rather than wrap.
- Do reuse the state colours by meaning (grey = low/inactive, tomato = attention, teal/blue =
  rest) rather than adding new hues, and keep every pair above 4.5:1 on both white and black.
- Don't let a meaning rest on colour alone; pair it with a glyph, as the states and tiers do.
- Don't colour the prompt or secondary hint, and never render a timer state in red.
- Do keep the ASCII icon set to plain ASCII; add any new state to both the emoji and ASCII
  tables at once.
- Don't introduce custom colours, fonts, or corner radii in the macOS client; it uses system
  styles and semantic colours only, and the tomato belongs to the icon and the README.
- Do keep the light/dark pairs in `theme.go` together; a new colour needs both values.
