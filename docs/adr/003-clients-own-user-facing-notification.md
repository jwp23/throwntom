# ADR-003: Clients own user-facing notification

## Context

ADR-001 put the timer, scheduler and reminders in a long-running Go daemon
(`throwntomd`) and made the macOS app a client of its JSON API. It left open
who presents a reminder to the user.

The daemon took that job. `internal/app`'s reminder loop plays a sound, and
throwntom-6qi added an actionable macOS notification with Snooze/Confirm
buttons so a reminder could be answered while the menu bar app was closed.
Because `UNUserNotificationCenter` refuses to work from a process without
bundle identity, that shipped as `throwntom-alert`: a small Swift executable
inside the app bundle, code-signed as the app, which the daemon spawns.

Two things then surfaced.

First, it does not work. Verified 2026-08-27: the banner appears with both
buttons, but clicking one does nothing — `snooze_until` stays null and the
reminder keeps ringing. macOS routes the response to the executable that
posted the notification, and `throwntom-alert` exits immediately after
posting, so the response has nowhere to land. The menu bar app's
`ReminderResponder` never fires even when the app is running.

Second, the approach is wrong regardless. `UNUserNotificationCenter` cannot
be used from a LaunchAgent at all — `bundleProxyForCurrentProcess` is nil and
posting fails with `UNErrorCodeNotificationsNotAllowed`. It is built for apps
and app extensions. `throwntom-alert` exists only to smuggle bundle identity
to a process that is not allowed to have it. And `throwntomd` is portable Go
with a Linux notifier path, so spawning a code-signed macOS helper puts
platform-specific presentation into the portable core.

Options considered:

1. Keep the helper alive with a run loop until the reminder is answered, so
   it can receive the response and call the daemon.
2. Have the daemon post notifications itself via cgo and Objective-C.
3. Move user-facing notification into the clients; the daemon publishes state.

## Decision

Option 3. The daemon owns timing and state and publishes changes on
`/v1/events`. Each client owns presentation on its own platform.

The macOS app is a persistent `LSUIElement` agent with real bundle identity.
It already subscribes to the event stream and already calls the daemon API
for every other action. On seeing `awaiting_confirm` it posts the
notification, handles the response in-process, and POSTs the verb — the same
path as any button in the app. `ThrowntomAlert` is deleted; the daemon keeps
no macOS notification code.

A consequence follows, and it is intended: **closing a client ends its
notifications.** A user who quits the menu bar app has stopped using that
client and should not keep being nagged by a process they cannot see. This is
how macOS menu bar utilities behave, and it is the user's expectation.

## Trade-offs

We gain a portable daemon, no spawned helper process, no cgo, and a response
path that works because the process holding the notification is the one that
posted it and stays alive.

We give up reminders while no client runs. That is the point of the decision
rather than a regression, but it means the daemon should not play a sound
that nothing is present to answer — the reminder is a client concern too. The
repeat bound from throwntom-6qi becomes a backstop rather than the fix.

It also means throwntom-6qi's original incident is answered differently than
it was implemented: quitting the app is the off switch.

Open questions this creates are tracked in throwntom-9ig.2 (how the daemon's
lifecycle, restart and config reload are exposed) and throwntom-ii1 (whether
the TUI likewise becomes a client rather than a second owner of state).
