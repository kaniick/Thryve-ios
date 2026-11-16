import SwiftUI

@main
struct ThryveApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var connection = Connection()

    init() {
        PodComponent.registerComponent()
        PartComponent.registerComponent()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(connection)
                .foregroundStyle(Theme.text1)
                .tint(Theme.podOK)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { BackgroundRefresh.schedule() }
        }
        // iOS wakes the app now and then to check the unit for notifications.
        .backgroundTask(.appRefresh(UnitNotifier.refreshTaskID)) {
            await BackgroundRefresh.run()
        }
    }
}

/// Connect first; once there's a unit (or the demo), Home.
struct RootView: View {
    @Environment(Connection.self) private var connection

    var body: some View {
        Group {
            if let api = connection.api {
                HomeView(store: HomeStore(api: api, stream: stream(for: connection.target), notifier: notifier(for: connection.target), liveActivities: true))
                    // A new unit or key is a new store, stream and all.
                    .id("\(String(describing: connection.target))|\(connection.apiKey)")
                    .task(id: "\(String(describing: connection.target))|\(connection.apiKey)") {
                        WateringActivities.attach(api, unitName: connection.name)
                        await PushRegistrar.shared.attach(connection.isDemo ? nil : api)
                    }
            } else {
                ConnectView()
            }
        }
        .background(Theme.app.ignoresSafeArea())
    }

    private func notifier(for target: Connection.Target?) -> UnitNotifier? {
        guard case .unit(let url)? = target else { return nil }
        return UnitNotifier(unitKey: url.absoluteString)
    }

    private func stream(for target: Connection.Target?) -> EventStream? {
        guard case .unit(let url)? = target else { return nil }
        return EventStream(baseURL: url, apiKey: connection.apiKey)
    }
}
