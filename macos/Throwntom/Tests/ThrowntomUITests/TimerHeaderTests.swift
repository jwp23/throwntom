// Tests/ThrowntomUITests/TimerHeaderTests.swift
import AppKit
import SwiftUI
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

// MARK: - TimerHeaderTests

/// The title was the one string in the window with a fixed line budget, so it was the one that
/// could be cut off. These lay every title the window can build into the width the window is
/// narrowest at, and hold the budget to what that measurement needs.
@MainActor
final class TimerHeaderTests: XCTestCase {

  // MARK: Internal

  /// The budget has to cover the longest title the window can actually build, not the longest
  /// anyone remembered. Fails the moment a limit is reintroduced that any real title overruns —
  /// which is what shipped: a budget of two, against a worst case several times that
  /// (throwntom-2jq). The failure message names the title and the size that overran it.
  func testTheTitleBudgetCoversEveryTitleTheWindowCanBuild() {
    let deepest = Self.deepestTitle()

    XCTAssertGreaterThanOrEqual(
      TimerHeader.titleLineLimit ?? Int.max,
      deepest.lines,
      "“\(deepest.title)” wraps to \(deepest.lines) lines at \(deepest.scale)× and would be cut off",
    )
  }

  /// The measurement is only evidence if it can fail, so this pins the defect itself: titles the
  /// window really builds really do outgrow two lines, at sizes nothing forbids. If this ever
  /// stops holding, the test above has gone quiet for a reason worth knowing about.
  func testTheLongestTitlesOutgrowTheTwoLinesTheyUsedToBeGiven() {
    let longest = "Done for today (reconnecting)"
    XCTAssertTrue(Self.everyTitle().contains(longest), "the window no longer builds “\(longest)”")

    // At the default size it already needs more than one line, so the old budget of two had
    // nothing spare for a longer phase name, a reworded wait, or a translation.
    XCTAssertGreaterThan(Self.lineCount(of: longest, pointSize: Self.largeTitlePointSize), 1)
    XCTAssertGreaterThan(Self.deepestTitle().lines, 2)
  }

  /// The sweep's whole claim is that it builds every title without anyone having to remember a
  /// new one, so each title that is not a phase name is pinned here. A dimension the sweep forgets
  /// costs nothing today and silently stops measuring the title that outgrows the width tomorrow.
  func testTheSweepBuildsTheTitlesThatAreNotPhaseNames() {
    let built = Self.everyTitle()
    for title in ["Snoozed", "Done for today", MainWindowContent.morningNudgeTitle] {
      XCTAssertTrue(built.contains(title), "the sweep no longer builds “\(title)”")
    }
  }

  /// Truncation is the failure being ruled out, so the header must not reintroduce it by another
  /// route: a scale factor would shrink text rather than cut it, which is the same readability
  /// problem wearing a different hat.
  func testTheTitleWrapsRatherThanShrinkingOrTruncating() {
    XCTAssertNil(TimerHeader.titleLineLimit)
  }

  /// Every statement `body` builds, spelled out as the type SwiftUI actually composed. A statement
  /// that stops being built — the mascot, the inner stack, the title, or either optional line —
  /// changes this string, whether or not that line is built for this particular content: the type
  /// is fixed by the source, not by the countdown/next-stage values in hand (`StatsPanelTests`
  /// draws the same distinction). TimerHeader.swift:24:5/25:7/27:7/28:9/34:11/37:11.
  func testBodyIsTheMascotAndTheTitleStackWithItsOptionalLines() {
    let content = MainWindowContent(
      state: makeState(phase: .idle),
      connection: .connected,
      status: .running,
      tasks: TaskList(),
      error: nil,
      panel: nil,
      now: .now,
    )

    XCTAssertEqual(
      shape(of: TimerHeader(content: content).body),
      "ModifiedContent<VStack<TupleView<(ModifiedContent<MascotView, _FlexFrameLayout>, ModifiedContent<VStack<"
        + "TupleView<(ModifiedContent<ModifiedContent<ModifiedContent<Text, _EnvironmentKeyWritingModifier<TextAlignment>>, "
        + "_EnvironmentKeyWritingModifier<Optional<Int>>>, _FixedSizeLayout>, Optional<Text>, Optional<Text>)>>, "
        + "LiveValue>)>>, _FlexFrameLayout>",
    )
  }

  /// `.fixedSize(horizontal: false, vertical: true)` on the title: compressible in width, so a long
  /// title wraps at whatever width the header is given instead of demanding its own single-line
  /// width, but not in height, so a squeezed header still draws the whole wrapped title rather
  /// than a fragment clipped to fit. Measured on the title `Text` pulled out of the built tree
  /// alone (`Self.titleView`), not the whole header, so nothing the mascot or the optional
  /// countdown/next lines draw can dilute — or, per the `StatsPanel` lesson, silently erode as they
  /// change — what only the title responds to.
  ///
  /// The longest title the window builds (`deepestTitle` above) is required: a short title like
  /// "Idle" already fits inside the squeeze on unmutated code (measured ink 26pt, indistinguishable
  /// from either mutant's clipped/single-line ink), so it exercises nothing. One render, squeezed in
  /// both dimensions at once, kills both booleans the same way `ShortcutHintTests` does: a
  /// `horizontal: true` mutant refuses to wrap so it never reaches past the squeezed height
  /// (measured ink 30pt); a `vertical: false` mutant wraps but is then clipped to the squeezed
  /// height (measured ink 26pt). Only the unmutated pairing does both — wraps into several lines
  /// and draws all of them (measured ink 126pt). TimerHeader.swift:32:34/32:51.
  func testTheTitleWrapsAndGrowsRatherThanBeingClippedWhenSqueezed() throws {
    let content = MainWindowContent(
      state: makeState(phase: .idle, dayEnded: true),
      connection: .reconnecting(attempt: 1),
      status: .reaching,
      tasks: TaskList(),
      error: nil,
      panel: nil,
      now: .now,
    )
    XCTAssertNil(content.countdown, "the countdown line would dilute a measurement of the title alone")
    XCTAssertNil(content.nextStage, "the next-stage line would dilute a measurement of the title alone")

    let titleView = try Self.titleView(of: content)
    let ink = try Self.inkHeight(
      of: titleView.frame(width: Self.squeezeWidth, height: Self.squeezeHeight, alignment: .top),
      width: Self.squeezeWidth,
      canvasHeight: 300,
    )

    XCTAssertGreaterThan(
      ink,
      Self.squeezeHeight * 2,
      "“\(content.title)” was clipped to its squeezed height instead of wrapping past it",
    )
  }

  // MARK: Private

  /// The default, and the enlargements the header must survive. Nothing here asserts that macOS
  /// hands the app a larger size on its own — the case for the change is the headroom the default
  /// leaves, which is none. These are the margin the title should have had.
  private static let textScales: [CGFloat] = [1, 1.2, 1.5, 2, 3]

  private static let largeTitlePointSize = NSFont.preferredFont(forTextStyle: .largeTitle).pointSize

  /// Narrow enough that the longest title needs several lines, and short enough that "clipped to
  /// one line" and "wrapped to several" are unmistakably different amounts of ink.
  private static let squeezeWidth: CGFloat = 120
  private static let squeezeHeight: CGFloat = 24

  /// The worst case across every title and every size: which one wraps deepest, and how far.
  private static func deepestTitle() -> (title: String, scale: CGFloat, lines: Int) {
    var worst = (title: "", scale: CGFloat(1), lines: 0)
    for title in everyTitle() {
      for scale in textScales {
        let lines = lineCount(of: title, pointSize: largeTitlePointSize * scale)
        if lines > worst.lines {
          worst = (title, scale, lines)
        }
      }
    }
    return worst
  }

  /// Every title `MainWindowContent` can produce, built through it rather than restated, so a new
  /// phase or a reworded wait is measured here without anyone remembering to add it. The flags
  /// beside the phase are swept too, not just the phase itself: three of the titles are owed to
  /// `snooze_until`, `day_ended` and `morning_pending` rather than to any state the daemon names.
  private static func everyTitle() -> Set<String> {
    let phases: [DaemonState.Phase] = [.idle, .work, .shortBreak, .longBreak, .lunch, .awaitingConfirm, .paused]
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
              for snoozeUntil in [nil, Date(timeIntervalSince1970: 600)] {
                for morningPending in [false, true] {
                  let state = makeState(
                    phase: phase,
                    morningPending: morningPending,
                    snoozeUntil: snoozeUntil,
                    dayEnded: dayEnded,
                  )
                  titles.insert(title(state: state, connection: connection, status: status))
                }
              }
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

  /// How many lines the string wraps to in the header's font at the window's narrowest content
  /// width. TextKit is a close proxy rather than SwiftUI's own layout — `Text` does not lay out
  /// through `NSLayoutManager` — so this is read for the shape of the answer (two lines, or four),
  /// never for an exact figure, and every assertion above compares rather than equates.
  private static func lineCount(of string: String, pointSize: CGFloat) -> Int {
    let attributed = NSAttributedString(string: string, attributes: [.font: boldLargeTitle(at: pointSize)])
    let storage = NSTextStorage(attributedString: attributed)
    let layout = NSLayoutManager()
    let container = NSTextContainer(
      size: NSSize(width: MainWindow.minimumContentWidth, height: .greatestFiniteMagnitude)
    )
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

  /// The font the header actually asks for — the `.largeTitle` text style with a bold trait, which
  /// carries that style's own tracking — rather than a plain system font at a matching size.
  private static func boldLargeTitle(at pointSize: CGFloat) -> NSFont {
    let style = NSFont.preferredFont(forTextStyle: .largeTitle)
    let bold = NSFontManager.shared.convert(style, toHaveTrait: .boldFontMask)
    return NSFont(descriptor: bold.fontDescriptor, size: pointSize) ?? bold
  }

  /// The exact statement `fixedSize(horizontal: false, vertical: true)` is attached to — the title
  /// `Text` alone, pulled out of the built tree rather than measured through the whole header, so
  /// nothing the mascot or the optional countdown/next lines draw can dilute what only the title
  /// responds to.
  private static func titleView(of content: MainWindowContent) throws -> AnyView {
    let inner = try unwrapped(try part(1, of: try tupleParts(of: try stackContent(of: try unwrapped(
      TimerHeader(content: content).body
    )))))
    let titlePart = try part(0, of: try tupleParts(of: try stackContent(of: inner)))
    let view = try XCTUnwrap(titlePart as? any View, "the title text was not a View: \(shape(of: titlePart))")
    return open(view)
  }

  private static func open(_ view: some View) -> AnyView {
    AnyView(view)
  }

  /// The height of the lowest non-white pixel row: how far the view actually drew, regardless of
  /// what size its enclosing frame reports upward. Technique from `ShortcutHintTests.inkHeight`.
  private static func inkHeight(of view: some View, width: CGFloat, canvasHeight: CGFloat) throws -> CGFloat {
    let renderer = ImageRenderer(
      content: view.frame(width: width, height: canvasHeight, alignment: .top).background(Color.white)
    )
    renderer.scale = 1
    let image = try XCTUnwrap(renderer.nsImage, "the view did not render")
    let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let data = try XCTUnwrap(cgImage.dataProvider?.data)
    let pixels = try XCTUnwrap(CFDataGetBytePtr(data))
    let bytesPerRow = cgImage.bytesPerRow

    var lastInkedRow = 0
    for y in 0 ..< cgImage.height {
      for x in 0 ..< cgImage.width {
        let offset = y * bytesPerRow + x * 4
        if pixels[offset] < 250 || pixels[offset + 1] < 250 || pixels[offset + 2] < 250 {
          lastInkedRow = y
          break
        }
      }
    }
    return CGFloat(lastInkedRow + 1)
  }

}
