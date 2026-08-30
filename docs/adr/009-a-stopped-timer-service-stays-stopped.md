# ADR-009: A stopped timer service stays stopped

## Context

ADR-006 gave the app Start and Stop for the timer service and made the daemon
independent of its clients: quitting the app does not stop the daemon. It did
not settle how long a stop lasts.

The implementation that shipped with it made a stop last one app session.
`DaemonClient.stopService()` cancels the event stream and sets the connection to
`stopped`, so nothing dials and nothing re-registers the launchd agent while the
app stays open. On the next launch the client dials from scratch, and after
three failed dials `ReconnectBackoff.registerAgentIfDue` asks launchd for the
daemon. So relaunching the app silently revived a service the user had switched
off — and with the app as a login item, that defeated Stop entirely.

Both readings had a case. Opening the app arguably means you want the timer.
Equally, a deliberate action that a relaunch undoes is not really an action.

Against persisting: a service that is off and says nothing produces a "why is
nothing happening" with no way back in, which is a worse failure than a timer
that came back uninvited.

Two other absent-service situations already existed and had to stay
distinguishable from this one. launchd refusing to start the daemon is a
failure, reported as "Timer service can't launch". launchd accepting the
request and no daemon ever arriving is a third, previously shown as "Starting
timer…" indefinitely.

## Decision

1. **A stop persists across app launches.** The intent is recorded, and a client
   that reads a stopped intent does not dial and does not ask launchd for the
   daemon. It stays stopped until the user presses Start Timer Service.
2. **The window says whose decision it was.** The stopped screen states that the
   user stopped the service and names the control that undoes it. Persistence is
   safe only because of that sentence; without it, the silence is the failure
   mode.
3. **The three absent situations are three distinct screens.** Stopped, refused
   and unanswered each get their own title and their own sentence. Dialling is
   not one of them: it keeps the phase it holds and reads as transient.
4. **Absence of a recorded intent means running.** A first launch and a client
   whose daemon died both want the daemon back. Only an explicit stop does not,
   so only an explicit stop keeps the client from dialling.

This supersedes ADR-006 on the lifetime of a stop. ADR-006's decisions (1) and
(3) stand as written; decision (2) was already superseded by ADR-008.

## Trade-offs

A user who forgets they pressed Stop gets no timer until they read the window
and press Start. That is accepted: the sentence is what makes it recoverable,
and the alternative silently overrides a deliberate choice.

Recording the intent puts one piece of client state outside the daemon, which
otherwise owns everything durable. It is deliberately the smallest possible
piece — one of two values — and it describes the user's wish for the service
rather than anything about the timer, which the daemon still owns alone.

Reporting an unanswered start after a delay means the window can accuse a daemon
that was merely slow. Re-asking launchd is not an alternative: registration is
unregister-then-register, so a second ask boots out the daemon the first one
started. Saying so and leaving the retry to the user is the only move that
cannot make the outage worse.
