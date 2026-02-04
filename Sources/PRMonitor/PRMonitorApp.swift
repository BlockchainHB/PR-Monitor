import SwiftUI

@main
struct PRMonitorApp: App {
    @StateObject private var container: AppContainer
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let container = AppContainer()
        _container = StateObject(wrappedValue: container)
        appDelegate.container = container
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(container.settingsStore)
                .environmentObject(container.authStore)
        }
    }
}
