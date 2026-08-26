# macOS app is a SwiftPM package assembled into a bundle by build.sh

## Decision

`macos/Throwntom/` is a Swift Package (`Package.swift`) with a library
target holding everything testable (`DaemonClient`, transport, `State`,
`Commands`) and an executable target holding the SwiftUI app. There is no
`.xcodeproj`. `macos/build.sh` runs `go build` for `throwntomd`, then
`swift build -c release`, then assembles `Throwntom.app` by hand (Info.plist
with `LSUIElement`, `Contents/Library/LaunchAgents/<label>.plist`, the
daemon binary) and ad-hoc signs it with `codesign --sign -`. Tests run with
`swift test` locally and `xcodebuild test` on the package in CI.

## Rationale

- There is no command-line way to generate an Xcode project; hand-writing
  `project.pbxproj` is brittle and every added file needs a project edit.
  SwiftPM discovers sources by directory.
- The SMAppService spike (`docs/spikes/smappservice-agent-registration/`)
  already proved a hand-assembled, ad-hoc signed bundle registers its
  launchd agent from any location with no prompt, so nothing Xcode-specific
  is needed for the bundle to work.
- `xcodebuild test` accepts a `Package.swift`, so CI does not lose
  anything.
- Xcode can still open the package for editing and debugging.
