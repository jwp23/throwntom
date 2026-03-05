# Toggleable Help Menu

## Problem

The daemon commands help text is always visible, taking up screen space. Users who know the commands don't need it permanently displayed.

## Design

Hide the help text by default, show a `?: help` hint instead. Pressing `?` toggles the full commands list on/off. When visible, the help appears in the same position it occupies today.

### Approach

Add a `showHelp` toggle to the Bubble Tea model. Split the current `HeaderLines` (which mixes mode info and help text) into two fields: persistent header lines and toggleable help lines.

### Changes

**`interactiveCallbacks` (`interactive_callbacks.go`)**
- Add `HelpLines []string` field alongside existing `HeaderLines`.

**`interactiveTeaModel` (`interactive_tea_model.go`)**
- Add `showHelp bool` field (default `false`).
- Add `helpLines []string` field, populated from `callbacks.HelpLines`.
- `updateKey`: when `?` is pressed and input buffer is empty, toggle `showHelp`. When input is non-empty, treat `?` as a normal character.
- `View`: always render `headerLines`. If `showHelp` is false, append `"?: help"`. If true, append `helpLines`.

**`modes.go`**
- `localModeCallbacks`: put mode/config lines in `HeaderLines`, `daemonCommandsHelp()` lines in `HelpLines`.
- `shellModeCallbacks`: put connection line in `HeaderLines`, `daemonCommandsHelp()` lines in `HelpLines`.

### Behavior

| State | Display |
|-------|---------|
| Start | Mode info, config, `?: help`, status, prompt |
| After `?` (empty input) | Mode info, config, full commands list, status, prompt |
| After `?` again | Back to hint |
| Typing `?` in a command | Normal character input, no toggle |
