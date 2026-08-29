import SwiftUI
import ThrowntomClient

// MARK: - StatsLoader

/// Fetches the dashboard once when the panel opens. The panel is a snapshot, not a live view:
/// the numbers change once per pomodoro, and reopening it is the refresh.
@Observable
@MainActor
final class StatsLoader {
  enum Outcome: Equatable {
    case loading
    case loaded([StatsRows.Row])
    case failed(String)
  }

  private(set) var outcome = Outcome.loading

  func load(from client: DaemonClient) async {
    do {
      outcome = .loaded(StatsRows.rows(try await client.stats()))
    } catch {
      outcome = .failed("Stats unavailable: \(error)")
    }
  }
}

// MARK: - StatsPanel

/// The `stats` command's summary as a label/value grid, opened under the timer with ⌘⇧D.
struct StatsPanel: View {

  // MARK: Internal

  let client: DaemonClient

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Stats").font(.caption).textCase(.uppercase).opacity(0.8)
      switch loader.outcome {
      case .loading:
        ProgressView().controlSize(.small)

      case .loaded(let rows):
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
          ForEach(rows, id: \.label) { row in
            GridRow {
              Text(row.label).opacity(0.8)
              Text(row.value).fontWeight(.semibold).monospacedDigit()
            }
          }
        }

      case .failed(let message):
        Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
    .task { await loader.load(from: client) }
  }

  // MARK: Private

  @State private var loader = StatsLoader()

}
