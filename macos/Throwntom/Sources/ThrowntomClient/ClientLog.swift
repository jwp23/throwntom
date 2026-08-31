import Foundation
import os

/// Where a failure the user was told about in a sentence leaves a record of what actually went
/// wrong.
///
/// The window shows fixed wording and never an error's own text, which is right: a socket errno
/// or a `ServiceManagement` domain is not something a reader can act on. The detail still has to
/// go somewhere, and this is where — Apple's unified log, off by default, kept by the system, and
/// readable after the fact with the command in docs/development.md.
///
/// It is a diagnostic channel and not a second way to word a failure: nothing here reaches a view.
public enum ClientLog {

  // MARK: Public

  /// The part of the app a failure came from, and the `category` a reader narrows `log show` to.
  public enum Area: String, CaseIterable, Sendable {
    /// Requests to the daemon and the event stream that carries its state.
    case daemon
    /// launchd, Login Items, and anything else macOS is asked to do on the app's behalf.
    case service
    /// Notification authorization and the reminder banners themselves.
    case reminders
    /// The task list and the editor that adds to it.
    case tasks
    /// The stats panel's one fetch.
    case stats
  }

  /// One line as it would be written. A value rather than a formatted string so a test can assert
  /// which area a catch site reported under, which is otherwise invisible.
  public struct Entry: Equatable, Sendable {
    public let area: Area
    public let message: String
  }

  /// Matches `CFBundleIdentifier` in macos/bundle/Info.plist, which is what the `subsystem`
  /// predicate in docs/development.md filters on.
  public static let subsystem = "com.jwp23.throwntom"

  /// Records that `operation` failed. `operation` is a fixed literal at every call site — never
  /// an interpolated command, task or draft — and `describe` admits no free text from the daemon,
  /// so no user content can reach the log through here.
  public static func failed(_ operation: String, in area: Area, error: Error) {
    sink(Entry(area: area, message: "\(operation) failed: \(describe(error))"))
  }

  /// Records a failure that arrives as a refusal rather than an `Error` — a framework call that
  /// answers `false` and says no more than that. `reason` is a fixed literal at every call site,
  /// for the same reason `describe` admits none of the error's own words.
  public static func refused(_ operation: String, in area: Area, reason: String) {
    sink(Entry(area: area, message: "\(operation) failed: \(reason)"))
  }

  // MARK: Internal

  /// Where a line goes. Replaced only by tests, which is the one way to see that a catch site
  /// recorded anything: the unified log is not readable from inside the process that wrote it.
  /// Internal rather than public: redirecting the whole diagnostic channel is not something a
  /// client of this module should be able to do.
  /// A `Logger` is built per line rather than cached per category. `os_log_create` is cached by
  /// the system, and the alternative — a dictionary keyed by `Area` — returns an optional, which
  /// would drop a line silently on a lookup that cannot fail. That is the wrong trade for a
  /// channel whose whole job is not losing things.
  nonisolated(unsafe) static var sink: @Sendable (Entry) -> Void = { entry in
    Logger(subsystem: subsystem, category: entry.area.rawValue)
      // `.public` because nothing here is private: `describe` admits no free text but our own
      // literals, a status code and an NSError's domain and code. Left at the default, every
      // line would read `<private>` and the channel would record nothing worth having.
      .error("\(entry.message, privacy: .public)")
  }

  /// An error reduced to its shape: a kind, and a status code, a wait or an `NSError` domain and
  /// code. Deliberately not the error's own words.
  ///
  /// `DaemonError.http`'s message is dropped rather than logged, and that is the whole reason this
  /// function exists instead of a string interpolation at each call site: the daemon quotes the
  /// request back in its refusals — `unknown command: %s` (internal/core/core.go) and the task
  /// grammar's own usage errors (internal/core/tasks.go) — so that message can contain whatever
  /// the user typed. The status code says as much as a log reader needs and cannot carry it.
  ///
  /// `localizedDescription` is not read for the same reason it is absent from the rest of this
  /// app: for the errors that actually arrive here it is `The operation couldn't be completed.
  /// (SMAppServiceErrorDomain error 1.)` — the domain and the code, wrapped in a sentence.
  static func describe(_ error: Error) -> String {
    if error is CancellationError {
      return "cancelled"
    }
    switch error as? DaemonError {
    case .transport(let reason):
      // Our own literals, or `String(describing:)` of a Network framework error: a POSIX name,
      // never anything the user wrote.
      return "transport: \(reason)"
    case .malformedResponse(let reason):
      return "malformed response: \(reason)"
    case .http(let status, _):
      return "http \(status)"
    case .timedOut(let after):
      return "timed out after \(after.components.seconds)s"
    case nil:
      // A Swift enum error bridges to a domain naming its type and a code numbering its case;
      // an associated value is not carried across, which is what keeps a payload out of the log.
      let cocoa = error as NSError
      return "\(cocoa.domain) \(cocoa.code)"
    }
  }

}
