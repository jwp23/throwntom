import Foundation
import Observation

/// Publishes the current time once a second so the countdown re-renders without daemon traffic.
@Observable @MainActor
public final class Ticker {

  // MARK: Lifecycle

  public init(interval: Duration = .seconds(1)) {
    self.interval = interval
  }

  // MARK: Public

  public private(set) var now = Date.now

  /// Idempotent: a second call adopts the running loop rather than starting a rival one.
  public func start() {
    guard task == nil else { return }
    task = Task {
      while !Task.isCancelled {
        try? await Task.sleep(for: interval)
        guard !Task.isCancelled else { return }
        now = Date.now
      }
    }
  }

  public func stop() {
    task?.cancel()
    task = nil
  }

  // MARK: Private

  private let interval: Duration
  private var task: Task<Void, Never>?

}
