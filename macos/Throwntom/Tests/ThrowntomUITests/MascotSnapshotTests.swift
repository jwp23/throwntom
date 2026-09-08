import AppKit
import SwiftUI
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

/// Renders the mascot offscreen. Every pose must produce an image; when `MASCOT_SNAPSHOT_DIR` is
/// set the images are also written as 2× PNGs for checking against rendered poses without launching
/// the app (`tools/mascot-snap.sh`).
@MainActor
final class MascotSnapshotTests: XCTestCase {

  // MARK: Internal

  func testEveryPoseRendersOffscreen() throws {
    for phase in Self.phases {
      let scheme = Palette.scheme(for: phase.phase)
      let pose = MascotPose.pose(for: phase.phase, pausedFrom: phase.pausedFrom)
      let image = try XCTUnwrap(render(pose: pose, frame: .still, scheme: scheme), phase.name)
      XCTAssertGreaterThan(image.size.width, 0, phase.name)
      try write(image, name: phase.name)
    }
  }

  func testMotionExtremesRenderOffscreen() throws {
    let yoyoDown = MotionFrame(
      bobDegrees: 0,
      blinking: false,
      yoyoDrop: MascotMotion.yoyoDropRange.upperBound,
      jumpLift: 0,
      zzzPhase: 0,
    )
    let jumpPeak = MotionFrame(bobDegrees: 0, blinking: false, yoyoDrop: 0, jumpLift: MascotMotion.jumpLift, zzzPhase: 0)
    let blink = MotionFrame(bobDegrees: MascotMotion.breatheDegrees, blinking: true, yoyoDrop: 0, jumpLift: 0, zzzPhase: 0)
    let extremes: [(name: String, pose: MascotPose, frame: MotionFrame, phase: DaemonState.Phase?)] = [
      ("idle-yoyo-down", .idle, yoyoDown, .idle),
      ("awaiting-confirm-jump", .awaitingConfirm, jumpPeak, .awaitingConfirm),
      ("work-blink", .work, blink, .work),
    ]
    for extreme in extremes {
      let image = try XCTUnwrap(
        render(pose: extreme.pose, frame: extreme.frame, scheme: Palette.scheme(for: extreme.phase)),
        extreme.name,
      )
      try write(image, name: extreme.name)
    }
  }

  /// The asleep pose doffs the crown: the cap replaces the stem and leaves for the night, so not
  /// one pixel of leaf green may show in the snoozed frame. The crown is drawn swept 8° to the
  /// right (`TomatoBodyView`), which pushes its tip out past any cap thin enough to match the
  /// design — the approved mockup resolves that by not drawing a crown at all, and so does the
  /// pose.
  func testTheSnoozedFrameShowsNoLeafGreen() throws {
    let image = try XCTUnwrap(render(pose: .asleep, frame: .still, scheme: Palette.snoozed))
    let tiff = try XCTUnwrap(image.tiffRepresentation)
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))

    var greens = 0
    for y in 0 ..< bitmap.pixelsHigh {
      for x in 0 ..< bitmap.pixelsWide where Self.isLeafGreen(bitmap.colorAt(x: x, y: y)) {
        greens += 1
      }
    }

    XCTAssertEqual(greens, 0, "leaf green shows through the nightcap")
  }

  /// The Z's are air, not prop: the approved mock draws them outside the character's −12° turn
  /// and its breathe, upright in the corner of the room. Rendered at the still frame, the middle
  /// and top Z's diagonals must cross their unrotated centres — under the character transform
  /// those spots are bare violet ground. Pixels are `40 + 4 × design` in the 2× snapshot (unit 2,
  /// 20pt padding).
  func testTheZsHangUprightInTheCorner() throws {
    let image = try XCTUnwrap(render(pose: .asleep, frame: .still, scheme: Palette.snoozed))
    let tiff = try XCTUnwrap(image.tiffRepresentation)
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))

    for centre in [CGPoint(x: 373, y: 178), CGPoint(x: 393, y: 140)] {
      let color = bitmap.colorAt(x: Int(centre.x), y: Int(centre.y))?.usingColorSpace(.deviceRGB)
      let cream = color.map { $0.redComponent > 0.85 && $0.greenComponent > 0.85 && $0.blueComponent > 0.8 } ?? false
      XCTAssertTrue(cream, "no upright Z stroke at \(centre)")
    }
  }

  /// A snooze is not a phase, so the asleep pose and the ground it wears are rendered on their own
  /// rather than through the sweep above. Mid-cycle as well as still: the Z's are the one motion
  /// whose still frame is not simply the absence of the moving one.
  func testTheSnoozedPoseAndItsHeaderRenderOffscreen() throws {
    let drifting = MotionFrame(bobDegrees: 0, blinking: false, yoyoDrop: 0, jumpLift: 0, zzzPhase: 0.4)
    for (name, frame) in [("snoozed", MotionFrame.still), ("snoozed-zzz-drift", drifting)] {
      let image = try XCTUnwrap(render(pose: .asleep, frame: frame, scheme: Palette.snoozed), name)
      XCTAssertGreaterThan(image.size.width, 0, name)
      try write(image, name: name)
    }

    let content = MainWindowContent(
      state: makeState(phase: .awaitingConfirm, snoozeUntil: Date(timeIntervalSince1970: 1_000_600)),
      connection: .connected,
      status: .running,
      tasks: TaskList(),
      error: nil,
      panel: nil,
      now: Date(timeIntervalSince1970: 1_000_000),
    )
    try write(try XCTUnwrap(snapshot(header(content)), "header-snoozed"), name: "header-snoozed")
  }

  func testHeaderRendersOffscreen() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    for phase in Self.phases {
      let content = MainWindowContent(
        state: phase.phase.map {
          makeState(phase: $0, phaseEndAt: now.addingTimeInterval(Self.headerCountdownDuration), pausedFrom: phase.pausedFrom)
        },
        connection: phase.phase == nil ? .connecting : .connected,
        status: phase.phase == nil ? .reaching : .running,
        tasks: TaskList(),
        error: nil,
        panel: nil,
        now: now,
      )
      if let phaseValue = phase.phase, Self.countdownPhases.contains(phaseValue) {
        XCTAssertNotNil(content.countdown, phase.name)
      }
      let image = try XCTUnwrap(snapshot(header(content)), "header-\(phase.name)")
      try write(image, name: "header-\(phase.name)")
    }
  }

  // MARK: Private

  /// A plausible time-left for a header screenshot: long enough to read as a real, in-progress phase.
  private static let headerCountdownDuration: TimeInterval = 15 * 60

  /// Phases `MainWindowContent.countdown` shows a value for (`MainWindowContent.swift`): the
  /// `phaseEndAt`-backed phases below, plus `.paused` from `pausedRemaining`. The rest show none
  /// regardless of `phaseEndAt`, so asserting on them here would be asserting on nothing.
  private static let countdownPhases: Set<DaemonState.Phase> = [.work, .shortBreak, .longBreak, .lunch, .meeting, .paused]

  private static let phases: [(name: String, phase: DaemonState.Phase?, pausedFrom: DaemonState.Phase)] = [
    ("work", .work, .idle),
    ("meeting", .meeting, .idle),
    ("short-break", .shortBreak, .idle),
    ("long-break", .longBreak, .idle),
    ("lunch", .lunch, .idle),
    ("idle", .idle, .idle),
    ("awaiting-confirm", .awaitingConfirm, .idle),
    ("paused", .paused, .work),
    ("disconnected", nil, .idle),
  ]

  private var outputDirectory: URL? {
    ProcessInfo.processInfo.environment["MASCOT_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
  }

  /// Leaf green as it survives gradients and antialiasing: green leads red and blue both, which
  /// nothing else on the snoozed frame's palette does — cream, sky, red, violet and outline all
  /// fail one of the margins.
  private static func isLeafGreen(_ color: NSColor?) -> Bool {
    guard let color = color?.usingColorSpace(.deviceRGB) else { return false }
    return color.greenComponent > 0.31
      && color.greenComponent > color.redComponent + 0.1
      && color.greenComponent > color.blueComponent + 0.1
  }

  private func header(_ content: MainWindowContent) -> some View {
    TimerHeader(content: content)
      .padding(16)
      .frame(width: 400)
      .background(content.scheme.ground.color)
      .foregroundStyle(content.scheme.text.color)
  }

  private func render(pose: MascotPose, frame: MotionFrame, scheme: PhaseScheme) -> NSImage? {
    snapshot(
      MascotCharacterView(pose: pose, frame: frame, scheme: scheme, unit: 2, animatesPoseChanges: true)
        .padding(20)
        .background(scheme.ground.color)
    )
  }

  private func snapshot(_ view: some View) -> NSImage? {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    return renderer.nsImage
  }

  private func write(_ image: NSImage, name: String) throws {
    guard let outputDirectory else { return }
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    let tiff = try XCTUnwrap(image.tiffRepresentation)
    let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    try png.write(to: outputDirectory.appendingPathComponent("\(name).png"))
  }

}
