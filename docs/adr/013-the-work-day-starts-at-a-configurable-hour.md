# ADR-013: The work day starts at a configurable hour

## Context

UAT (GH #161) found that "Done for the Day" stays on screen after the
calendar day rolls over. Investigation showed the rollover logic itself was
sound — `AdvanceDay` already clears the day-ended flag when the date changes —
but the check is lazy, running only when a command, status read, or restart
touches the core. The macOS client is push-only, so overnight nothing
publishes and the stale banner just sits there.

Fixing only the laziness would not have been enough, because the boundary was
in the wrong place. Walking an overnight shift through a midnight boundary
breaks the user's stated expectations twice:

- A pomodoro running at midnight carries over, but the day's counters and the
  long-break cadence reset mid-shift, and a pomodoro finishing at 12:20am is
  credited to a day the worker doesn't think has started yet.
- Done for the Day set at 2am has nothing to clear it that morning — it was
  set on today's date — so the worker wakes to a "Done for today" banner that
  lasts until the next midnight.

The expectations, as ruled by Joe: a running pomodoro continues until Done
for the Day is set, and the morning shows plain idle, never yesterday's
done-for-day state.

A constraint recorded on throwntom-bxd.8 shapes any fix: the code holds two
independent definitions of "a day" — the engine compares calendar dates for
its work date, and the reminder keys its once-a-day record by formatted date.
A boundary that moves one without the other leaves the counters and the
morning reminder disagreeing about which day it is.

A "Start Day" affordance was also floated in UAT.

## Decision

1. **The work day runs from a configurable day-start hour to the next, not
   midnight to midnight.** The config default is `04:00`. A 10pm–2am shift is
   one day: counters and long-break cadence hold across midnight, and Done
   for the Day set at 2am clears at 4am while the worker sleeps. A 9-to-5
   user never notices the boundary moved.

2. **One shared day-identity function owns the boundary.** The engine's
   same-day test and the reminder's day key both derive from it, so the two
   definitions of a day cannot drift apart. `AdvanceDay` remains the single
   owner of the new-day reset.

3. **Rollover is eager.** The daemon observes the boundary on its own tick
   and publishes the rolled-over state, instead of waiting for the next
   command or status read. Clients never render yesterday's day-ended state
   past the boundary.

4. **No Start Day action.** The first start of the day already begins the
   work day and clears the day-ended flag; an explicit affordance would add a
   state and a ritual without enabling anything.

## Trade-offs

- A config knob nobody may ever turn. Accepted because the boundary must
  thread through as a parameter anyway once it leaves midnight, and a second
  user with an overnight shift past 4am is plausible.
- "Today's" counters no longer match the calendar date near midnight — a
  pomodoro at 1am counts toward yesterday's total. That is the point: the
  total tracks the work day, not the calendar day.
- The eager tick does slightly more work than a lazy check, in exchange for
  push-only clients staying truthful.
