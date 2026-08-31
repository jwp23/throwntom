// Tests/ThrowntomUITests/TimerHeaderTests.swift
import AppKit
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

// MARK: - TimerHeaderTests

/// The title is the one thing in the window that carried a fixed line budget, so it is the one
/// thing that could truncate. These measure the real `.largeTitle` bold metrics at the window's
/// narrowest content width and assert every title the window can build still reads in full.
final class TimerHeaderTests: XCTestCase {

  // MARK: Internal

  /// At the default text size the two-line budget was exactly consumed — `Pomodoro (reconnecting)`,
  /// `Done for today (reconnecting)` and `Timer service isn’t answering` each take both lines with
  /// nothing to spare — so any increase in text size truncated the title (throwntom-2jq). Measured
  /// rather than assumed: at twice the default size those same titles need three and four lines.
  func testEveryTitleTheWindowCanBuildFitsItsLineBudget() {
    for title in Self.everyTitle() {
      for scale in Self.textScales {
        let needed = Self.lineCount(of: title, pointSize: Self.largeTitlePointSize * scale)
        guard let budget = TimerHeader.titleLineLimit else { continue }
        XCTAssertLessThanOrEqual(
          needed,
          budget,
          "“\(title)” needs \(needed) lines at \(scale)× but the title is capped at \(budget)",
        )
      }
    }
  }

  /// The measurement above is only evidence if it can fail: a budget of two really is exceeded by
  /// a title the window builds, at a text size the window does not forbid.
  func testTheLongestTitlesExceedTwoLinesAtLargerTextSizes() {
    let longest = "Done for today (reconnecting)"
    XCTAssertTrue(Self.everyTitle().contains(longest), "the window no longer builds \(longest)")
    XCTAssertEqual(Self.lineCount(of: longest, pointSize: Self.largeTitlePointSize), 2)
    XCTAssertGreaterThan(Self.lineCount(of: longest, pointSize: Self.largeTitlePointSize * 2), 2)
  }

  /// Truncation is the failure being ruled out, so the header must not reintroduce it by another
  /// route: a scale factor would shrink the text a reader enlarged on purpose.
  func testTheTitleWrapsRatherThanShrinkingOrTruncating() {
    XCTAssertNil(TimerHeader.titleLineLimit)
  }

  // MARK: Private

  /// The window's minimum width (`MainWindow.swift`) less its 16pt padding on each side: the
  /// narrowest the title is ever laid out in.
  private static let contentWidth: CGFloat = 288

  /// The default and the enlargements a reader can ask for. The app pins no `dynamicTypeSize`
  /// anywhere, so a larger one reaches this text unchanged.
  private static let textScales: [CGFloat] = [1, 1.2, 1.5, 2, 3]

  private static let largeTitlePointSize = NSFont.preferredFont(forTextStyle: .largeTitle).pointSize

  /// Every title `MainWindowContent` can produce, built through it rather than restated, so a new
  /// phase or a reworded wait is measured here without anyone remembering to add it.
  private static func everyTitle() -> Set<String> {
    let phases: [DaemonState.Phase] = [.idle, .work, .shortBreak, .longBreak, .awaitingConfirm, .paused]
    let connections: [DaemonClient.Connection] = [
      .connected,
      .connecting,
      .reconnecting(attempt: 1),
      .startingDaemon,
      .stopped,
    ]
    var titles = Set<String>()
    for connection in connections {
      for registrationFailed in [false, true] {
        for startStalled in [false, true] {
          let status = ServiceStatus.of(
            connection: connection,
            registrationFailed: registrationFailed,
            startStalled: startStalled,
          )
          for phase in phases {
            for dayEnded in [false, true] {
              let state = makeState(phase: phase, dayEnded: dayEnded)
              titles.insert(title(state: state, connection: connection, status: status))
            }
          }
          titles.insert(title(state: nil, connection: connection, status: status))
        }
      }
    }
    return titles
  }

  private static func title(
    state: DaemonState?,
    connection: DaemonClient.Connection,
    status: ServiceStatus,
  ) -> String {
    MainWindowContent(
      state: state,
      connection: connection,
      status: status,
      tasks: TaskList(active: [], completed: []),
      error: nil,
      panel: nil,
      now: Date(timeIntervalSince1970: 0),
    ).title
  }

  /// How many lines the string takes when laid out in the header's font at `contentWidth`.
  private static func lineCount(of string: String, pointSize: CGFloat) -> Int {
    let attributed = NSAttributedString(
      string: string,
      attributes: [.font: NSFont.systemFont(ofSize: pointSize, weight: .bold)],
    )
    let storage = NSTextStorage(attributedString: attributed)
    let layout = NSLayoutManager()
    let container = NSTextContainer(size: NSSize(width: contentWidth, height: .greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    storage.addLayoutManager(layout)
    layout.addTextContainer(container)
    layout.ensureLayout(for: container)
    var count = 0
    var glyph = 0
    while glyph < layout.numberOfGlyphs {
      var line = NSRange()
      _ = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &line)
      glyph = NSMaxRange(line)
      count += 1
    }
    return count
  }

}
