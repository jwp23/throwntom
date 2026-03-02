package main

import "testing"

func TestParseKeyEventPrintable(t *testing.T) {
	ev, ok := parseKeyEvent([]byte{'a'})
	if !ok {
		t.Fatal("expected printable input to parse")
	}
	if ev.kind != keyPrintable {
		t.Fatalf("expected key kind %v, got %v", keyPrintable, ev.kind)
	}
	if ev.r != 'a' {
		t.Fatalf("expected rune %q, got %q", 'a', ev.r)
	}
}

func TestParseKeyEventBackspace(t *testing.T) {
	for _, b := range []byte{0x08, 0x7f} {
		ev, ok := parseKeyEvent([]byte{b})
		if !ok {
			t.Fatalf("expected backspace byte %x to parse", b)
		}
		if ev.kind != keyBackspace {
			t.Fatalf("expected key kind %v for byte %x, got %v", keyBackspace, b, ev.kind)
		}
	}
}

func TestParseKeyEventEnter(t *testing.T) {
	for _, b := range []byte{'\r', '\n'} {
		ev, ok := parseKeyEvent([]byte{b})
		if !ok {
			t.Fatalf("expected enter byte %x to parse", b)
		}
		if ev.kind != keyEnter {
			t.Fatalf("expected key kind %v for byte %x, got %v", keyEnter, b, ev.kind)
		}
	}
}
