import SwiftUI
import ThrowntomClient

@main
struct ThrowntomApp: App {
    @State private var client: DaemonClient
    @State private var ticker: Ticker
    @State private var model = TaskWindowModel()
    @State private var responder: ReminderResponder
    private let registrar = SMAppServiceRegistrar()

    /// Client and ticker start here, not in a view's onAppear: the popover content only appears when opened.
    init() {
        let client = DaemonClient(
            transport: UnixSocketTransport(socketPath: DaemonPaths.socketPath),
            registrar: SMAppServiceRegistrar())
        let ticker = Ticker()
        let responder = ReminderResponder(client: client)
        client.start()
        ticker.start()
        responder.start()
        _client = State(initialValue: client)
        _ticker = State(initialValue: ticker)
        _responder = State(initialValue: responder)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(client: client, ticker: ticker, registrar: registrar)
        } label: {
            Text(MenuBarTitle.text(state: client.state, connection: client.connection, now: ticker.now))
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
