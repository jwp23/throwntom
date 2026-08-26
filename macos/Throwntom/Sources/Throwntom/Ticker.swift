import Foundation
import Observation

/// Publishes the current time once a second so the countdown re-renders without daemon traffic.
@Observable @MainActor
final class Ticker {
    private(set) var now = Date()
    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = Date()
            }
        }
    }
}
