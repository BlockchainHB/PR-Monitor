import SwiftUI
import UserNotifications

/// Settings in the style of System Settings: a sidebar with the account at the top and colored
/// icon tiles, and a detail pane whose toolbar holds that pane's actions.
struct SettingsView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationSplitView {
            SettingsSidebar()
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .navigationTitle(router.settingsTab.title)
        }
        .frame(minWidth: 720, idealWidth: 760, minHeight: 500, idealHeight: 560)
        // A menu bar app has no Dock icon; while Settings is open it behaves like a regular app
        // (Dock, ⌘-Tab, app menu), then steps back when the window closes.
        .onAppear { DockPresence.show() }
        .onDisappear { DockPresence.hide() }
    }

    @ViewBuilder
    private var detail: some View {
        switch router.settingsTab {
        case .account: AccountPane()
        case .general: GeneralPane()
        case .notifications: NotificationsPane()
        case .repositories: RepositoriesPane()
        case .agents: AgentsPane()
        }
    }
}

enum DockPresence {
    @MainActor static func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    @MainActor static func hide() {
        NSApp.setActivationPolicy(.accessory)
    }
}

extension AppRouter.SettingsTab {
    var title: String {
        switch self {
        case .account: "Account"
        case .general: "General"
        case .notifications: "Notifications"
        case .repositories: "Repositories"
        case .agents: "Agents"
        }
    }

    var symbol: String {
        switch self {
        case .account: "person.crop.circle.fill"
        case .general: "gearshape"
        case .notifications: "bell.badge"
        case .repositories: "book.closed"
        case .agents: "sparkles"
        }
    }
}

// MARK: - Sidebar

/// A neutral sidebar in the current iOS/iPadOS style. A system `List` always paints selection in the
/// accent color, so rows are drawn here:
/// - selection is a soft gray pill with primary-color text, and the selected glyph goes to full strength;
/// - hover is a barely-there wash, shown instantly, so it never competes with the selection;
/// - glyphs take the label's font, in a fixed-width column so titles align;
/// - everything scales with the user's Sidebar Icon Size preference, and arrow keys move the selection.
private struct SettingsSidebar: View {
    @Environment(AppRouter.self) private var router
    @Environment(Account.self) private var account
    @FocusState private var isFocused: Bool

    private let order: [AppRouter.SettingsTab] = [.account, .general, .notifications, .repositories, .agents]

    var body: some View {
        ScrollView {
            // One even rhythm between rows; only the account row gets breathing room below it.
            VStack(alignment: .leading, spacing: 2) {
                ForEach(order, id: \.self) { tab in
                    SidebarRow(tab: tab, isSelected: router.settingsTab == tab) {
                        router.settingsTab = tab
                    }
                    .padding(.bottom, tab == .account ? 8 : 0)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { move(by: -1) }
        .onKeyPress(.downArrow) { move(by: 1) }
        // Wide enough for "Notifications" at the Large sidebar size, like System Settings.
        .navigationSplitViewColumnWidth(min: 215, ideal: 230, max: 300)
        .frame(minWidth: 215)
    }

    private func move(by offset: Int) -> KeyPress.Result {
        guard let index = order.firstIndex(of: router.settingsTab) else { return .ignored }
        router.settingsTab = order[max(0, min(order.count - 1, index + offset))]
        return .handled
    }
}

private struct SidebarRow: View {
    let tab: AppRouter.SettingsTab
    let isSelected: Bool
    let select: () -> Void

    @Environment(Account.self) private var account
    @Environment(\.sidebarRowSize) private var rowSize
    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            Group {
                if tab == .account {
                    AccountSidebarRow(credential: account.credential)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: tab.symbol)
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .frame(width: iconColumn)
                        Text(tab.title)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .font(font)
                    .frame(minHeight: rowHeight)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: 8))
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    // Hover is a whisper; only the selection reads as a solid pill.
                    .fill(.primary.opacity(isSelected ? 0.1 : (isHovered ? 0.035 : 0)))
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(tab == .account ? (account.credential?.login ?? "Account") : tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var font: Font {
        switch rowSize {
        case .small: .subheadline
        case .large: .title3
        default: .body
        }
    }

    private var rowHeight: CGFloat {
        switch rowSize {
        case .small: 24
        case .large: 34
        default: 28
        }
    }

    private var iconColumn: CGFloat {
        switch rowSize {
        case .small: 16
        case .large: 22
        default: 18
        }
    }
}

/// The account row at the top of the sidebar, like System Settings' Apple Account row. It's the
/// only custom row, so it follows the user's Sidebar Icon Size preference the way system rows do.
private struct AccountSidebarRow: View {
    let credential: Account.Credential?
    @Environment(\.sidebarRowSize) private var rowSize

    var body: some View {
        HStack(spacing: 8) {
            Avatar(login: credential?.login, size: avatarSize)
            VStack(alignment: .leading, spacing: 0) {
                Text(credential?.login ?? "Connect GitHub")
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(credential == nil ? "Not signed in" : "GitHub")
                    .font(subtitleFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    private var avatarSize: CGFloat {
        switch rowSize {
        case .small: 24
        case .large: 34
        default: 28
        }
    }

    private var subtitleFont: Font {
        switch rowSize {
        case .small: .caption
        case .large: .callout
        default: .subheadline
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @Environment(AppSettings.self) private var settings
    @State private var launchesAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Check for changes", selection: $settings.refreshInterval) {
                    ForEach(AppSettings.refreshIntervals, id: \.self) { interval in
                        Text(Duration.seconds(interval).formatted(.units(allowed: [.minutes, .seconds], width: .wide)))
                            .tag(interval)
                    }
                }
            } footer: {
                Text("How often to check while agents are running. PR Monitor checks less often once everything has settled, and waits out GitHub rate limits on its own.")
            }

            Section("Menu Bar") {
                Picker("Show pull requests", selection: $settings.scope) {
                    Text("All open pull requests").tag(AppSettings.Scope.all)
                    Text("Only ones I opened").tag(AppSettings.Scope.authored)
                }
                Toggle("Hide drafts", isOn: $settings.hidesDrafts)
                Toggle(isOn: $settings.showsAttentionCount) {
                    Text("Show attention count")
                    Text("The number of pull requests that are failing or ready for your review.")
                }
                Toggle(isOn: $settings.usesColoredStatusIcon) {
                    Text("Use colored status icon")
                    Text("Otherwise the icon matches the other menu bar icons.")
                }
            }

            Section {
                Toggle("Open at login", isOn: $launchesAtLogin)
                    .onChange(of: launchesAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            } footer: {
                if let loginItemError {
                    Text(loginItemError).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            loginItemError = LoginItem.requiresApproval ? "Approve PR Monitor in System Settings › General › Login Items." : nil
        } catch {
            loginItemError = error.localizedDescription
            launchesAtLogin = LoginItem.isEnabled
        }
    }
}

// MARK: - Notifications

private struct NotificationsPane: View {
    @Environment(AppSettings.self) private var settings
    @State private var status: UNAuthorizationStatus?
    @State private var testResult: String?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle(isOn: $settings.notifiesWhenSettled) {
                    Text("When agents finish")
                    Text("Once every check and review bot has reported on the latest push.")
                }
                Toggle(isOn: $settings.notifiesOnNewFeedback) {
                    Text("When new feedback arrives")
                    Text("If a bot leaves review threads after a pull request has settled.")
                }
                Toggle(isOn: $settings.notifiesPerAgent) {
                    Text("When each agent finishes")
                    Text("A separate notification for every check and reviewer.")
                }
            }

            Section {
                LabeledContent {
                    if status == .denied {
                        Button("Open System Settings…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                        }
                    } else {
                        Button("Send Test") {
                            Task {
                                testResult = await Notifier().postTest() ? "Sent" : "Couldn't send"
                                status = await Notifier().authorizationStatus()
                            }
                        }
                        .disabled(!Notifier.isAvailable)
                    }
                } label: {
                    Text("Permission")
                    Text(testResult ?? permissionDescription)
                }
            }
        }
        .formStyle(.grouped)
        .task { status = await Notifier().authorizationStatus() }
    }

    private var permissionDescription: String {
        guard Notifier.isAvailable else { return "Unavailable when running outside the app bundle." }
        return switch status {
        case .authorized, .provisional, .ephemeral: "Allowed"
        case .denied: "Turned off in System Settings"
        default: "Not requested yet"
        }
    }
}
