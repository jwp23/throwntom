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
    let yoyoDown = MotionFrame(bobDegrees: 0, blinking: false, yoyoDrop: MascotMotion.yoyoDropRange.upperBound, jumpLift: 0)
    let jumpPeak = MotionFrame(bobDegrees: 0, blinking: false, yoyoDrop: 0, jumpLift: MascotMotion.jumpLift)
    let blink = MotionFrame(bobDegrees: MascotMotion.breatheDegrees, blinking: true, yoyoDrop: 0, jumpLift: 0)
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
      let header = TimerHeader(content: content)
        .padding(16)
        .frame(width: 400)
        .background(content.scheme.ground.color)
        .foregroundStyle(content.scheme.text.color)
      let image = try XCTUnwrap(snapshot(header), "header-\(phase.name)")
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
