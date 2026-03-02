package main

type promptState struct {
	input string
}

type keyKind int

const (
	keyPrintable keyKind = iota
	keyBackspace
	keyEnter
)

type keyEvent struct {
	kind keyKind
	r    rune
}

func applyKey(state promptState, ev keyEvent) (promptState, string, bool) {
	switch ev.kind {
	case keyPrintable:
		state.input += string(ev.r)
		return state, "", true
	case keyBackspace:
		chars := []rune(state.input)
		if len(chars) > 0 {
			state.input = string(chars[:len(chars)-1])
		}
		return state, "", true
	case keyEnter:
		submitted := state.input
		state.input = ""
		return state, submitted, true
	default:
		return state, "", false
	}
}
