import SwiftUI
import UserNotifications
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            RepositoriesSettingsTab()
                .tabItem {
                    Label("Repositories", systemImage: "folder")
                }
            AgentsSettingsTab()
                .tabItem {
                    Label("Agents", systemImage: "cpu")
                }
        }
        .padding(20)
        .frame(width: 600, height: 500)
    }
}

// MARK: - General Settings Tab

private struct GeneralSettingsTab: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var authStore: AuthStore

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var notificationStatusDetail = ""

    var body: some View {
        Form {
            accountSection
            pollingSection
            notificationsSection
        }
        .formStyle(.grouped)
        .onAppear {
            loadNotificationStatus()
        }
    }

    // MARK: Account

    @ViewBuilder
    private var accountSection: some View {
        Section {
            HStack(spacing: 8) {
                if authStore.isSignedIn {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("Signed in")
                        .accessibilityValue("Connected to GitHub")
                } else {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.yellow)
                        .accessibilityHidden(true)
                    Text("Not signed in")
                        .accessibilityValue("Not connected to GitHub")
                }
                Spacer()
                if authStore.isSignedIn {
                    Button("Sign Out") {
                        authStore.signOut()
                    }
                } else {
                    Button(authStore.isSigningIn ? "Signing In..." : "Sign In") {
                        authStore.signIn(clientId: settings.githubClientId)
                    }
                    .disabled(authStore.isSigningIn || settings.githubClientId.isEmpty)
                }
            }

            if let flow = authStore.deviceFlow {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter this code at GitHub:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(flow.userCode)
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                    Button {
                        NSWorkspace.shared.open(flow.verificationURL)
                    } label: {
                        Label("Open GitHub", systemImage: "arrow.up.right.square")
                    }
                }
            }

            TextField("GitHub OAuth Client ID", text: $settings.githubClientId)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .accessibilityLabel("GitHub OAuth Client ID")

            if let message = authStore.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Account")
        } footer: {
            Text("Create an OAuth app at github.com/settings/developers")
        }
    }

    // MARK: Polling

    private var pollingSection: some View {
        Section {
            Picker("Polling Interval", selection: $settings.pollingIntervalSeconds) {
                Text("30 seconds").tag(30)
                Text("1 minute").tag(60)
                Text("2 minutes").tag(120)
                Text("5 minutes").tag(300)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Polling")
        } footer: {
            Text("When no open PRs are found, refreshes every 10 minutes.")
        }
    }

    // MARK: Notifications

    private var notificationsSection: some View {
        Section {
            Toggle("All agents complete", isOn: .constant(true))
                .disabled(true)
                .accessibilityValue("Always enabled")
            Toggle("Review summary", isOn: $settings.notifySummary)
            Toggle("Per-agent completion", isOn: $settings.notifyPerAgent)
            Button("Send Test Notification") {
                sendTestNotification()
            }
            .accessibilityLabel("Send a test notification")
        } header: {
            Text("Notifications")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Receive notifications when agent checks complete on your PRs")
                Text(notificationStatusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityValue(notificationStatusDetail)
            }
        }
    }

    // MARK: Helpers

    private func loadNotificationStatus() {
        guard notificationsAvailable else {
            notificationStatus = .notDetermined
            notificationStatusDetail = "Notifications unavailable in this build."
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { notiSettings in
            Task { @MainActor in
                notificationStatus = notiSettings.authorizationStatus
                switch notiSettings.authorizationStatus {
                case .authorized:
                    notificationStatusDetail = "Notifications are allowed in System Settings."
                case .denied:
                    notificationStatusDetail = "Notifications are blocked. Enable PR Monitor in System Settings > Notifications."
                case .notDetermined:
                    notificationStatusDetail = "Notifications haven't been requested yet."
                case .provisional:
                    notificationStatusDetail = "Notifications are in provisional mode."
                case .ephemeral:
                    notificationStatusDetail = "Notifications are temporary (ephemeral)."
                @unknown default:
                    notificationStatusDetail = "Notification permission status unknown."
                }
            }
        }
    }

    private func sendTestNotification() {
        guard notificationsAvailable else {
            notificationStatusDetail = "Notifications unavailable in this build."
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            let content = UNMutableNotificationContent()
            content.title = "PR Monitor"
            content.body = "Test notification."
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
            loadNotificationStatus()
        }
    }

    private var notificationsAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }
}

// MARK: - Repositories Settings Tab

private struct RepositoriesSettingsTab: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var authStore: AuthStore

    @State private var newRepoText = ""
    @State private var repoSearch = ""
    @State private var availableRepos: [RepoDTO] = []
    @State private var isLoadingRepos = false
    @State private var repoLoadError: String?

    private var filteredAvailableRepos: [RepoDTO] {
        let trimmed = repoSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return availableRepos }
        return availableRepos.filter { $0.fullName.localizedCaseInsensitiveContains(trimmed) }
    }

    private var canAddRepo: Bool {
        let trimmed = newRepoText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "/")
        return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty
    }

    var body: some View {
        Form {
            trackedReposSection
            addRepoSection
            browseGitHubSection
            if !availableRepos.isEmpty {
                filterSection
                availableReposSection
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Tracked Repos

    private var trackedReposSection: some View {
        Section {
            if settings.repos.isEmpty {
                Text("No repositories added yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach($settings.repos) { $repo in
                    Toggle(repo.fullName, isOn: $repo.isEnabled)
                        .contextMenu {
                            Button("Remove", role: .destructive) {
                                settings.repos.removeAll { $0.id == repo.id }
                            }
                        }
                }
                .onDelete { indexSet in
                    settings.repos.remove(atOffsets: indexSet)
                }
            }
        } header: {
            Text("Tracked Repositories")
        }
    }

    // MARK: Add Repo

    private var addRepoSection: some View {
        Section {
            HStack {
                TextField("owner/repo", text: $newRepoText)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                    .onSubmit { addRepo() }
                    .accessibilityLabel("Repository name in owner/repo format")
                Button("Add") { addRepo() }
                    .disabled(!canAddRepo)
            }
        } header: {
            Text("Add Repository")
        }
    }

    // MARK: Browse GitHub

    private var browseGitHubSection: some View {
        Section {
            Button {
                loadRepos()
            } label: {
                if isLoadingRepos {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Fetching repositories...")
                    }
                } else {
                    Label("Fetch from GitHub", systemImage: "arrow.down.circle")
                }
            }
            .disabled(isLoadingRepos || !authStore.isSignedIn)

            if !authStore.isSignedIn {
                Text("Sign in required to fetch repositories.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = repoLoadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Browse GitHub Repositories")
        } footer: {
            if !availableRepos.isEmpty {
                Text("\(availableRepos.count) repositories available")
            } else {
                Text("Fetch your repositories to add them to tracking")
            }
        }
    }

    // MARK: Filter & Available

    private var filterSection: some View {
        Section {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search repositories", text: $repoSearch)
                    .textFieldStyle(.roundedBorder)
                if !repoSearch.isEmpty {
                    Button {
                        repoSearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Clear search")
                    .accessibilityLabel("Clear search")
                }
            }
        } header: {
            Text("Filter")
        }
    }

    private var availableReposSection: some View {
        Section {
            ForEach(filteredAvailableRepos) { repo in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(repo.fullName)
                        if repo.isPrivate {
                            Label("Private", systemImage: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Toggle("", isOn: bindingForRepo(repo))
                        .labelsHidden()
                        .accessibilityLabel("Track \(repo.fullName)")
                }
            }
        } header: {
            Text("Available Repositories")
        } footer: {
            if !repoSearch.isEmpty {
                Text("Showing \(filteredAvailableRepos.count) of \(availableRepos.count) repositories")
            }
        }
    }

    // MARK: Helpers

    private func bindingForRepo(_ repo: RepoDTO) -> Binding<Bool> {
        Binding<Bool>(
            get: {
                settings.repos.first(where: { $0.fullName == repo.fullName })?.isEnabled ?? false
            },
            set: { enabled in
                settings.setRepoEnabled(owner: repo.owner.login, name: repo.name, enabled: enabled)
            }
        )
    }

    private func addRepo() {
        if settings.addRepo(from: newRepoText) != nil {
            newRepoText = ""
        }
    }

    private func loadRepos() {
        guard authStore.isSignedIn else {
            repoLoadError = "Sign in to fetch repos."
            return
        }
        repoLoadError = nil
        isLoadingRepos = true

        let client = GitHubClient(tokenProvider: { authStore.token })
        Task {
            do {
                let repos = try await client.fetchAllViewerRepos()
                let sorted = repos.sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
                await MainActor.run {
                    availableRepos = sorted
                    isLoadingRepos = false
                }
            } catch {
                await MainActor.run {
                    repoLoadError = error.localizedDescription
                    isLoadingRepos = false
                }
            }
        }
    }
}

// MARK: - Agents Settings Tab

private struct AgentsSettingsTab: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var authStore: AuthStore

    @State private var newAgentName = ""
    @State private var newAgentCheckPattern = ""
    @State private var newAgentCommentAuthor = ""
    @State private var isDetectingAgents = false
    @State private var agentDetectError: String?

    var body: some View {
        Form {
            quickSetupSection
            configuredAgentsSection
            addAgentSection
        }
        .formStyle(.grouped)
    }

    // MARK: Quick Setup

    private var quickSetupSection: some View {
        Section {
            Button {
                detectAgents()
            } label: {
                if isDetectingAgents {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Detecting agents...")
                    }
                } else {
                    Label("Auto-detect from Open PRs", systemImage: "sparkles")
                }
            }
            .disabled(isDetectingAgents || !authStore.isSignedIn || settings.enabledRepos.isEmpty)

            if let error = agentDetectError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if settings.enabledRepos.isEmpty {
                Text("Enable repositories first")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Quick Setup")
        } footer: {
            Text("Automatically find agents from your pull requests")
        }
    }

    // MARK: Configured Agents

    @ViewBuilder
    private var configuredAgentsSection: some View {
        Section {
            if settings.agents.isEmpty {
                Text("No agents configured yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            } else {
                ForEach($settings.agents) { $agent in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(agent.displayName.isEmpty ? "Unnamed Agent" : agent.displayName)
                                    .font(.headline)
                                if !agent.checkNamePattern.isEmpty {
                                    Text("Check: \(agent.checkNamePattern)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) {
                                settings.agents.removeAll { $0.id == agent.id }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove agent")
                            .accessibilityLabel("Remove \(agent.displayName)")
                        }

                        DisclosureGroup("Edit") {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Display Name", text: $agent.displayName)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Check Name Pattern", text: $agent.checkNamePattern)
                                    .textFieldStyle(.roundedBorder)
                                    .disableAutocorrection(true)
                                TextField("Comment Author Login", text: $agent.commentAuthor)
                                    .textFieldStyle(.roundedBorder)
                                    .disableAutocorrection(true)
                            }
                        }
                        .font(.caption)
                    }
                }
                .onDelete { indexSet in
                    settings.agents.remove(atOffsets: indexSet)
                }
            }
        } header: {
            Text("Configured Agents")
        } footer: {
            Text("Each agent monitors specific checks and comments on PRs")
        }
    }

    // MARK: Add Agent

    private var addAgentSection: some View {
        Section {
            TextField("Display Name", text: $newAgentName)
                .textFieldStyle(.roundedBorder)
            TextField("Check Name Pattern", text: $newAgentCheckPattern)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
            TextField("Comment Author Login", text: $newAgentCommentAuthor)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
            Button("Add Agent") {
                let agent = AgentConfig(
                    displayName: newAgentName,
                    checkNamePattern: newAgentCheckPattern,
                    commentAuthor: newAgentCommentAuthor
                )
                guard !agent.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                settings.agents.append(agent)
                newAgentName = ""
                newAgentCheckPattern = ""
                newAgentCommentAuthor = ""
            }
            .disabled(newAgentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text("Add New Agent")
        } footer: {
            Text("Agents match GitHub check runs and comment authors")
        }
    }

    // MARK: Helpers

    private func detectAgents() {
        guard authStore.isSignedIn else {
            agentDetectError = "Sign in to detect agents."
            return
        }
        guard !settings.enabledRepos.isEmpty else {
            agentDetectError = "Enable at least one repo."
            return
        }
        agentDetectError = nil
        isDetectingAgents = true

        let client = GitHubClient(tokenProvider: { authStore.token })
        let service = AgentDiscoveryService(client: client)

        Task {
            do {
                let discovered = try await service.discoverAgents(repos: settings.enabledRepos)
                await MainActor.run {
                    mergeAgents(discovered)
                    isDetectingAgents = false
                }
            } catch {
                await MainActor.run {
                    agentDetectError = error.localizedDescription
                    isDetectingAgents = false
                }
            }
        }
    }

    private func mergeAgents(_ discovered: [AgentConfig]) {
        for agent in discovered {
            let exists = settings.agents.contains { existing in
                normalize(existing.displayName) == normalize(agent.displayName)
                    || normalize(existing.checkNamePattern) == normalize(agent.checkNamePattern)
                    || (!agent.commentAuthor.isEmpty && normalize(existing.commentAuthor) == normalize(agent.commentAuthor))
            }
            if !exists {
                settings.agents.append(agent)
            }
        }
    }

    private func normalize(_ value: String) -> String {
        let lowered = value.lowercased()
        let removedBot = lowered.replacingOccurrences(of: "[bot]", with: "")
        let allowed = removedBot.filter { $0.isLetter || $0.isNumber }
        return allowed
    }
}
