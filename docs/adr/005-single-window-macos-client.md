# ADR-005: The macOS client is one phase-coloured window, not a menu bar app

## Context

ADR-001 shipped the macOS client as an `LSUIElement` menu bar app: a
ticking countdown in the menu bar, a control popover under it, and a
separate Tasks window. The first weeks of daily use (throwntom-9ig)
found the shape wrong for how the timer is actually used:

- The countdown was never looked at. During a pomodoro the point is not
  to watch the clock; what matters is which phase you are in, how long
  the break is, and how many pomodoros are done.
- On a large display the menu bar corner is far from where the eye and
  the mouse are, so answering "phase over, confirm?" meant a long mouse
  trip to a small popover.
- An `LSUIElement` app is invisible to ⌘-Tab, so there was no keyboard
  route to the app at all.
- Two surfaces (popover and window) with their own menus and buttons
  duplicated every action and produced bugs where one surface lacked
  items the other had (throwntom-afo).
- The stock popover and window had none of the personality of the icon
  and README, which the design language says is the product's register.

The desired flow is: hear the sound or see the notification → ⌘-Tab (or
click the Dock) → act with a shortcut or a button.

## Decision

The macOS client is a regular Dock application with exactly one window.
The window's ground colour is the timer phase (jewel-tone versions of the
TUI state palette), the header is a mascot slot beside the phase name and
countdown, today's pomodoros are drawn as tomatoes grouped into
long-break blocks, and the valid timer verbs are chips with their
shortcuts visible. Focused tasks show in the window; the full task list
and the stats summary are panels that expand the window on ⌘T and ⌘⇧D.
There is no menu bar item, no global hotkey and no typed command prompt.

> Amended 2026-08-29 (throwntom-6pc.2): the stats panel opens on ⌘⇧I, not
> ⌘⇧D. The decision above is unchanged; only that key was rebound.

At phase end the client notifies, bounces the Dock and recolours the
window; it never activates itself.

Options considered and rejected:

- *Keep the menu bar countdown alongside the window.* Rejected because
  the countdown had no observed value and a second surface is exactly
  the duplication this decision removes. Cheap to add back if missed.
- *Spotlight-style panel on a global hotkey, staying menu-bar-only.*
  Rejected: needs Carbon hotkey glue and still leaves the app out of
  ⌘-Tab.
- *Typed command prompt in the window, as in the TUI.* Rejected in
  favour of ⌘ chords only; a text field owning the keyboard blocks
  single-key shortcuts and adds a second input model.
- *Evolve the existing views.* Rejected: the views are the part that
  was disliked. `ThrowntomClient`'s existing transport, actions and
  task editing model are kept unchanged (it gains `DaemonClient.stats()`
  and `StatsSummary` for the new stats panel); only `ThrowntomUI` is
  rewritten.

## Trade-offs

- A Dock icon and a window are more presence than a menu bar item. The
  user asked for that: the window is meant to be parked in view and to
  be loud about the phase.
- A phase-coloured ground reverses `DESIGN.md`'s rule that colour is
  applied to the status line only; that rule now applies to the TUI
  alone, and the macOS palette gets its own tokens and an AA-contrast
  test.
- Rewriting the UI target discards working view code; the model and
  transport layers, where the fixed bugs live, are untouched.
- Floating the window above others while awaiting confirmation, and
  the mascot in the slot, are deferred so the first cut is the minimal
  flow. The layout reserves the mascot's space so adding it does not
  move anything.
