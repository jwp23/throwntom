import SwiftUI
import ThrowntomClient

@main
struct ThrowntomApp: App {
    @State private var client: DaemonClient
    @State private var ticker: Ticker
    private let registrar = SMAppServiceRegistrar()

    /// Client and ticker start here, not in a view's onAppear: the popover content only appears when opened.
    init() {
        let client = DaemonClient(
            transport: UnixSocketTransport(socketPath: DaemonPaths.socketPath),
            registrar: SMAppServiceRegistrar())
        let ticker = Ticker()
        client.start()
        ticker.start()
        _client = State(initialValue: client)
        _ticker = State(initialValue: ticker)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(client: client, ticker: ticker, registrar: registrar)
        } label: {
            Text(MenuBarTitle.text(state: client.state, connection: client.connection, now: ticker.now))
        }
        .menuBarExtraStyle(.window)
    }
}
