# ADR-011: The window grows with its content, it does not scroll

## Context

ADR-005 made the macOS client one window: a single vertical stack whose panels
expand it downward. Opening the tasks panel with ⌘T makes the window taller;
closing it shrinks it back. The window's height is a function of what it is
showing.

Fixing a title-overflow bug (throwntom-2jq) raised a wider question. There is
no `ScrollView` anywhere in `ThrowntomUI`, so if content is ever taller than
the window can be, the overflow is simply unreachable. At large accessibility
text sizes that looked plausible: the app styles almost everything with text
styles (`.largeTitle`, `.title2`, `.body`, `.caption`), which Apple documents
as scaling with the system text-size setting.

A `ScrollView` was built and measured. Two findings decided it.

**The overflow could not be reproduced.** `dynamicTypeSize` has no effect on
macOS: `.large` and `.accessibility5` both produced content exactly 503pt
tall. Setting the system preference directly did not change the layout either.
Nobody has yet made this app's content grow with the text-size setting, so the
condition the scroll view exists to handle is unobserved.

**A scroll view costs panel expansion.** A `ScrollView` proposes unbounded
height to its content, which erases the content's minimum. Measured against
`main`: `contentMinSize` height went from 303pt (512pt with the tasks panel
open) to **0**. The window stopped growing when a panel opened — ⌘T rendered
byte-identically to no panel at all — and could be dragged down to a ~32pt
sliver. At the scene's default 360×420 the bottom chip clipped.

The daily view at 360×536 was byte-identical either way, so the cost is not
visible until a panel is opened, which is exactly when it matters.

## Decision

The window grows with its content. It does not scroll.

`ScrollView` is not used to hold the window's stack. Panel expansion is the
mechanism by which content becomes reachable, as ADR-005 described.

This is a decision about a trade, not a discovery that scrolling is wrong:
a certain, daily cost was rejected in favour of a hypothetical, unobserved
benefit. If the overflow is ever actually seen — content clipped with no way
to reach it — that observation reopens this, and the answer then is likely to
be a design that keeps both, driving a window minimum from the content while
allowing scroll beyond it. That is real machinery, and it is not worth
building for a problem nobody has hit.

## Trade-offs

We keep a window whose size tells the truth about what it contains, and we
keep ⌘T doing something visible.

We accept that if content ever does exceed the window's maximum height, the
excess is unreachable rather than scrollable. The window is resizable, which
mitigates but does not solve it.

We accept that the accessibility text-size question is unresolved rather than
answered. Text styles are used throughout, so scaling ought to apply; it was
not observed to. Whether that is a macOS behaviour, a SwiftUI one, or
something about this app is not established here.
