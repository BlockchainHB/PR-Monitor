import Foundation

@MainActor
final class AppContainer: ObservableObject {
    let settingsStore: SettingsStore
    let authStore: AuthStore
    let appState: AppState

    init() {
        let settings = SettingsStore()
        let auth = AuthStore()
        self.settingsStore = settings
        self.authStore = auth
        self.appState = AppState(settingsStore: settings, authStore: auth)
    }
}
