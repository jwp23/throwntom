import SwiftUI
import ThrowntomClient

let mainWindowID = "main"

// MARK: - MainWindow

/// The whole app: phase-coloured ground, timer header, garden, chips, notes, focus, and the
/// optional panel. Everything it shows is decided by `MainWindowContent`.
struct MainWindow: View {

  /// The gap between the window's stacked sections.
  static let sectionSpacing: CGFloat = 12

  /// The narrowest the window goes, and the margin inside it. Named rather than written into the
  /// modifiers below because the width left for text is the difference between them, which
  /// `TimerHeaderTests` measures the title against; two literals would let the window narrow while
  /// the measurement went on checking the width it used to have.
  static let minimumWidth: CGFloat = 320

  static let contentPadding: CGFloat = 16

  /// How wide text is actually laid out at the narrowest the window goes.
  static let minimumContentWidth = minimumWidth - contentPadding * 2

  /// Extra space above the service chip, on top of `sectionSpacing`. It is not one of the timer
  /// verbs above it — it turns the whole timer service off, and a service the user stops stays
  /// stopped — so it must not read as another one. The Timer menu separates the same two groups
  /// with a divider; here the separation is positional, which needs no rule colour of its own and
  /// overstates nothing: stopping discards no progress (ADR-006), so a destructive tint would lie.
  static let serviceChipGap: CGFloat = 12

  let environment: AppEnvironment

  /// Everything the window draws for this moment. A property rather than a `let` in `body` so
  /// `escape()` can ask what is actually on screen instead of re-deriving the rule. Named apart
  /// from the `content` each caller binds it to, so neither has to be written `self.content` —
  /// which the formatter strips, leaving a line that reads as assigning to itself.
  var windowContent: MainWindowContent {
    MainWindowContent(
      state: environment.client.state,
      connection: environment.client.connection,
      status: environment.client.serviceStatus,
      tasks: environment.client.tasks,
      error: environment.client.unresolvedError,
      panel: environment.windowModel.panel,
      now: environment.ticker.now,
    )
  }

  var body: some View {
    let content = windowContent
    VStack(spacing: Self.sectionSpacing) {
      TimerHeader(content: content)
      if let garden = content.garden {
        TomatoGardenView(garden: garden)
      }
      ActionChips(content: content, client: environment.client, model: environment.windowModel)
      if environment.windowModel.isEnteringSnooze {
        SnoozeEntryRow(client: environment.client, model: environment.windowModel)
      }
      // Snoozing withdraws the reminder banner, so without this line an active snooze has no
      // representation on screen at all.
      if let snoozeNote = content.snoozeNote {
        // The window's second live countdown, and it gets the headline's treatment for the same
        // reason: the minutes left move on their own, so VoiceOver is told to re-read rather than
        // trust what it last said. Not announced, for the same reason the headline is not.
        Text(snoozeNote).font(.caption)
          .accessibilityAddTraits(.updatesFrequently)
      }
      ServiceChip(content: content, client: environment.client)
        .padding(.top, Self.serviceChipGap)
      CommandChips(environment: environment, scheme: content.scheme)
      WindowNotes(error: content.error, notice: content.notice, responder: environment.responder)
      FocusSection(tasks: content.focused)
      if content.panel == .tasks {
        TasksPanel(environment: environment, scheme: content.scheme)
      }
      if content.panel == .stats {
        StatsPanel(client: environment.client, scheme: content.scheme)
      }
    }
    .padding(Self.contentPadding)
    .frame(minWidth: Self.minimumWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(content.scheme.ground.color)
    .background(WindowElevator(floating: WindowElevation.floats(
      during: environment.client.state,
      connection: environment.client.connection,
    )))
    .foregroundStyle(content.scheme.text.color)
    .animation(.easeOut(duration: 0.25), value: content.scheme)
    .animation(.easeOut(duration: 0.25), value: content.panel)
    .onExitCommand { escape() }
    .sheet(isPresented: Bindable(environment.windowModel).showsShortcuts) {
      ShortcutSheet(environment: environment)
    }
    // The reminder can be answered from the notification or the keyboard while the duration
    // field is open. Clearing the flag rather than just hiding the row matters: a flag left set
    // behind a hidden row makes Escape answer something invisible, and puts the field back
    // unbidden — stealing the keyboard — the next time a reminder arrives.
    .onChange(of: content.chips.contains(.snooze)) { _, canSnooze in
      if !canSnooze {
        environment.windowModel.isEnteringSnooze = false
      }
    }
    .onChange(of: environment.client.tasks, initial: true) { syncModel() }
    .onChange(of: environment.client.state?.focusedTaskIds, initial: true) { syncModel() }
    .task { await trackAuthorization() }
  }

  /// Reads the notification permission now and again whenever the user comes back, so granting it
  /// in System Settings clears the note without a relaunch.
  func trackAuthorization() async {
    await environment.responder.refreshAuthorization()
    let activations = NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification)
    for await _ in activations {
      await environment.responder.refreshAuthorization()
    }
  }

  /// Copies the daemon's task list and focus into the model the list and menus read from.
  func syncModel() {
    environment.model.sync(tasks: environment.client.tasks, focusedTaskIDs: environment.client.state?.focusedTaskIds)
  }

  /// Escape closes whatever is open on top first; with nothing open it cancels a task edit. A
  /// panel the window is declining to draw counts as nothing open.
  func escape() {
    if !environment.windowModel.dismiss(panelIsShown: windowContent.panel != nil) {
      environment.model.cancelEdit()
    }
  }

}
