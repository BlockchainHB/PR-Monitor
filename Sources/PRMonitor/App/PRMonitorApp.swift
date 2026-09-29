import SwiftUI

@main
struct PRMonitorApp: App {
    @State private var settings: AppSettings
    @State private var account: Account
    @State private var monitor: Monitor
    @State private var router = AppRouter()

    init() {
        #if DEBUG
        Diagnostics.runIfRequested()
        Snapshots.runIfRequested()
        PortfolioShots.runIfRequested()
        #endif
        let settings = AppSettings()
        let account = Account()
        let monitor = Monitor(settings: settings, account: account, notifier: Notifier())
        _settings = State(initialValue: settings)
        _account = State(initialValue: account)
        _monitor = State(initialValue: monitor)
        monitor.start()
        #if DEBUG
        SettingsWindowPreview.runIfRequested()
        Showcase.runIfRequested()
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel()
                .environment(monitor)
                .environment(settings)
                .environment(account)
                .environment(router)
        } label: {
            MenuBarLabel(
                summary: monitor.summary,
                count: settings.showsAttentionCount ? monitor.attentionCount : 0,
                isColored: settings.usesColoredStatusIcon
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(monitor)
                .environment(settings)
                .environment(account)
                .environment(router)
        }
        .windowResizability(.contentMinSize)
    }
}

/// Lets any view send the user to a specific Settings tab.
@Observable
@MainActor
final class AppRouter {
    enum SettingsTab: Hashable {
        case account, general, notifications, repositories, agents
    }

    var settingsTab: SettingsTab = .general

    /// Opens Settings on a given tab and brings it forward. A menu bar app has no Dock icon, so
    /// without activating, the window would open behind whatever the user was doing.
    func showSettings(_ tab: SettingsTab? = nil, using openSettings: OpenSettingsAction) {
        if let tab { settingsTab = tab }
        DockPresence.show()
        openSettings()
    }
}
