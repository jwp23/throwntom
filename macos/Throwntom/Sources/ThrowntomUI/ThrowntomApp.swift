import SwiftUI
import ThrowntomClient

/// The app's entry point, built here rather than in the executable target so everything it
/// wires together stays in a library the tests can import.
public struct ThrowntomApp: App {
    @State private var client: DaemonClient
    @State private var ticker: Ticker
    @State private var model = TaskWindowModel()
    private let registrar = SMAppServiceRegistrar()

    /// Client and ticker start here, not in a view's onAppear: the popover content only appears when opened.
    public init() {
        let client = DaemonClient(
            transport: UnixSocketTransport(socketPath: DaemonPaths.socketPath),
            registrar: SMAppServiceRegistrar())
        let ticker = Ticker()
        client.start()
        ticker.start()
        _client = State(initialValue: client)
        _ticker = State(initialValue: ticker)
    }

    public var body: some Scene {
        MenuBarExtra {
            PopoverView(client: client, ticker: ticker, registrar: registrar)
        } label: {
            Text(ConnectionStatus.text(state: client.state, connection: client.connection, now: ticker.now))
        }
        .menuBarExtraStyle(.window)

        Window("Tasks", id: taskWindowID) {
            TaskWindow(client: client, model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 420, height: 360)
        .commands { AppMenus(client: client, model: model) }
    }
}
