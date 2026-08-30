import Foundation

// MARK: - ServiceIntent

/// Whether the user wants a timer service running. Stopping one is a deliberate act, so it is
/// recorded and honoured on the next launch rather than undone by the reconnect loop asking
/// launchd for the daemon again.
public enum ServiceIntent: String, Sendable {
  case running
  case stopped
}

// MARK: - ServiceIntentStore

/// Where the intent is kept between launches. Not `Sendable`: the only thing that reads or writes
/// it is `DaemonClient`, which is `@MainActor`, and `UserDefaults` is not a `Sendable` type.
public protocol ServiceIntentStore {
  func loadIntent() -> ServiceIntent
  func save(_ intent: ServiceIntent)
}

// MARK: - MemoryServiceIntentStore

/// An intent that lasts as long as the object holding it, and reaches nothing outside this
/// process. It is the default a `DaemonClient` is built with, so that constructing one never
/// writes to the user's defaults by accident; the app's composition root (`AppEnvironment.live`)
/// is the single place that asks for the persistent store instead.
public final class MemoryServiceIntentStore: ServiceIntentStore {

  // MARK: Lifecycle

  public init(_ intent: ServiceIntent = .running) {
    stored = intent
  }

  // MARK: Public

  public func loadIntent() -> ServiceIntent {
    stored
  }

  public func save(_ intent: ServiceIntent) {
    stored = intent
  }

  // MARK: Private

  private var stored: ServiceIntent

}

// MARK: - UserDefaultsServiceIntentStore

/// The intent in the app's user defaults.
///
/// Anything but a recorded stop reads as running, which is what keeps the three situations apart:
/// a first launch has written nothing, a client whose daemon died has written `running`, and both
/// want the daemon back. Only an explicit Stop does not, so only an explicit Stop is allowed to
/// keep the client from dialling.
public struct UserDefaultsServiceIntentStore: ServiceIntentStore {

  // MARK: Lifecycle

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  // MARK: Public

  public func loadIntent() -> ServiceIntent {
    defaults.string(forKey: Self.key).flatMap(ServiceIntent.init(rawValue:)) ?? .running
  }

  public func save(_ intent: ServiceIntent) {
    defaults.set(intent.rawValue, forKey: Self.key)
  }

  // MARK: Internal

  /// Internal rather than private so the tests can write a value no build of this app wrote and
  /// check that an unreadable record does not read as an instruction to keep the timer down.
  static let key = "com.jwp23.throwntom.serviceIntent"

  // MARK: Private

  private let defaults: UserDefaults

}
