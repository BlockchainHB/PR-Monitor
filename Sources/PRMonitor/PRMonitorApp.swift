import SwiftUI

@main
struct PRMonitorApp: App {
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var authStore: AuthStore
    @StateObject private var appState: AppState

    init() {
        let settings = SettingsStore()
        let auth = AuthStore()
        _settingsStore = StateObject(wrappedValue: settings)
        _authStore = StateObject(wrappedValue: auth)
        _appState = StateObject(wrappedValue: AppState(settingsStore: settings, authStore: auth))
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(appState)
                .environmentObject(authStore)
        } label: {
            StatusBarLabel(status: appState.overallStatus)
        }

        Settings {
            SettingsView()
                .environmentObject(settingsStore)
                .environmentObject(authStore)
                .frame(minWidth: 760, minHeight: 520)
        }
        .windowResizability(.contentSize)
    }
}
