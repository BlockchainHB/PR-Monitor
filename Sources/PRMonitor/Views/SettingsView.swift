import SwiftUI
import AppKit

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case github
    case repositories
    case agents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .github:
            return "GitHub"
        case .repositories:
            return "Repositories"
        case .agents:
            return "Agents"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .github:
            return "key"
        case .repositories:
            return "folder"
        case .agents:
            return "cpu"
        }
    }
}

struct SettingsView: View {
    @AppStorage("settingsPane") private var settingsPane: String = SettingsPane.general.rawValue
    @State private var selection: SettingsPane? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.systemImage)
                    .tag(pane)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180, idealWidth: 200)
        } detail: {
            switch selection ?? .general {
            case .general:
                GeneralSettingsPane()
            case .github:
                GitHubSettingsPane()
            case .repositories:
                RepositoriesSettingsPane()
            case .agents:
                AgentsSettingsPane()
            }
            .navigationTitle((selection ?? .general).title)
            .frame(minWidth: 560)
        }
        .onAppear {
            selection = SettingsPane(rawValue: settingsPane) ?? .general
        }
        .onChange(of: selection) { newValue in
            guard let newValue else { return }
            settingsPane = newValue.rawValue
        }
    }
}

private struct GeneralSettingsPane: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            Section("Refresh") {
                Picker("Polling Interval", selection: $settings.pollingIntervalSeconds) {
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                    Text("5 minutes").tag(300)
                }
                .pickerStyle(.segmented)
                Text("When no open PRs are found, refreshes every 10 minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Toggle("All agents complete", isOn: .constant(true))
                    .disabled(true)
                Toggle("Per-agent completion", isOn: $settings.notifyPerAgent)
                Text("Receive notifications when agent checks complete on your PRs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }
}

private struct GitHubSettingsPane: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var authStore: AuthStore

    var body: some View {
        Form {
            Section("Authentication") {
                HStack(alignment: .center, spacing: 12) {
                    StatusBadge(isActive: authStore.isSignedIn,
                                activeText: "Signed in",
                                inactiveText: "Signed out")
                    Spacer()
                    if authStore.isSignedIn {
                        Button("Sign Out") {
                            authStore.signOut()
                        }
                    }
                }

                TextField("Client ID", text: $settings.githubClientId)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)

                if authStore.isSignedIn == false {
                    Button(authStore.isSigningIn ? "Signing In…" : "Sign In with Device Code") {
                        authStore.signIn(clientId: settings.githubClientId)
                    }
                    .disabled(authStore.isSigningIn || settings.githubClientId.isEmpty)
                }

                if let flow = authStore.deviceFlow {
                    GroupBox("Device Code") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Enter this code at GitHub:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(flow.userCode)
                                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                                .textSelection(.enabled)
                            Button("Open GitHub") {
                                NSWorkspace.shared.open(flow.verificationURL)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let message = authStore.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Create an OAuth app at github.com/settings/developers")
            }
        }
        .padding(20)
    }
}

private struct RepositoriesSettingsPane: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var authStore: AuthStore
    @State private var selectedRepos: Set<RepoConfig.ID> = []
    @State private var isAddSheetPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Tracked Repositories")
                    .font(.headline)
                Spacer()
                Button {
                    isAddSheetPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add repository")
                Button {
                    removeSelectedRepos()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Remove selected")
                .disabled(selectedRepos.isEmpty)
            }

            if settings.repos.isEmpty {
                emptyState(
                    title: "No repositories",
                    message: "Add repositories to start monitoring PRs.",
                    systemImage: "tray"
                )
            } else {
                Table(settings.repos, selection: $selectedRepos) {
                    TableColumn("Repository") { repo in
                        Text(repo.fullName)
                            .lineLimit(1)
                    }
                    TableColumn("Tracking") { repo in
                        Toggle("", isOn: bindingForRepo(repo))
                            .labelsHidden()
                    }
                    .width(min: 90, ideal: 110)
                }
                .frame(minHeight: 260)
            }

            Text("Use the add button to include repositories manually or from GitHub.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .sheet(isPresented: $isAddSheetPresented) {
            AddRepositorySheet()
                .environmentObject(settings)
                .environmentObject(authStore)
        }
    }

    private func removeSelectedRepos() {
        let ids = selectedRepos
        settings.repos.removeAll { ids.contains($0.id) }
        selectedRepos.removeAll()
    }

    private func bindingForRepo(_ repo: RepoConfig) -> Binding<Bool> {
        Binding(
            get: {
                settings.repos.first(where: { $0.id == repo.id })?.isEnabled ?? false
            },
            set: { enabled in
                settings.setRepoEnabled(owner: repo.owner, name: repo.name, enabled: enabled)
            }
        )
    }
}

private struct AddRepositorySheet: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var authStore: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var newRepoText = ""
    @State private var repoSearch = ""
    @State private var availableRepos: [RepoDTO] = []
    @State private var isLoadingRepos = false
    @State private var repoLoadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Add Manually") {
                HStack {
                    TextField("owner/name", text: $newRepoText)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                        .onSubmit {
                            addRepo()
                        }
                    Button("Add") {
                        addRepo()
                    }
                    .disabled(!canAddRepo)
                }
            }

            GroupBox("GitHub") {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        loadRepos()
                    } label: {
                        if isLoadingRepos {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Fetching repositories…")
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
                }
            }

            if availableRepos.isEmpty {
                emptyState(
                    title: "No repositories loaded",
                    message: "Fetch your GitHub repositories to add them quickly.",
                    systemImage: "tray"
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Available Repositories")
                        .font(.headline)
                    List(filteredAvailableRepos) { repo in
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
                        }
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 200)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 460)
        .searchable(text: $repoSearch, placement: .toolbar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private var canAddRepo: Bool {
        let trimmed = newRepoText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "/")
        return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty
    }

    private func addRepo() {
        if settings.addRepo(from: newRepoText) != nil {
            newRepoText = ""
        }
    }

    private var filteredAvailableRepos: [RepoDTO] {
        let trimmed = repoSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return availableRepos }
        return availableRepos.filter { $0.fullName.localizedCaseInsensitiveContains(trimmed) }
    }

    private func bindingForRepo(_ repo: RepoDTO) -> Binding<Bool> {
        Binding(
            get: {
                settings.repos.first(where: { $0.fullName == repo.fullName })?.isEnabled ?? false
            },
            set: { enabled in
                settings.setRepoEnabled(owner: repo.owner.login, name: repo.name, enabled: enabled)
            }
        )
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

private struct AgentsSettingsPane: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var authStore: AuthStore
    @State private var selectedAgents: Set<AgentConfig.ID> = []
    @State private var isDetectingAgents = false
    @State private var agentDetectError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Configured Agents")
                    .font(.headline)
                Spacer()
                Button {
                    addAgent()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add agent")
                Button {
                    removeSelectedAgents()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Remove selected")
                .disabled(selectedAgents.isEmpty)

                Button {
                    detectAgents()
                } label: {
                    Label("Auto-detect", systemImage: "sparkles")
                }
                .disabled(isDetectingAgents || !authStore.isSignedIn || settings.enabledRepos.isEmpty)
                .help("Detect agents from open pull requests")
            }

            if isDetectingAgents {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Detecting agents…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let error = agentDetectError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if settings.enabledRepos.isEmpty {
                Text("Enable repositories first to auto-detect agents.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if settings.agents.isEmpty {
                emptyState(
                    title: "No agents",
                    message: "Add an agent to start tracking checks and comments.",
                    systemImage: "cpu"
                )
            } else {
                Table(settings.agents, selection: $selectedAgents) {
                    TableColumn("Name") { agent in
                        Text(agent.displayName.isEmpty ? "Unnamed Agent" : agent.displayName)
                            .lineLimit(1)
                    }
                    TableColumn("Check Pattern") { agent in
                        Text(agent.checkNamePattern)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    TableColumn("Comment Author") { agent in
                        Text(agent.commentAuthor)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(minHeight: 220)

                GroupBox("Details") {
                    if let index = selectedAgentIndex {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Display Name", text: $settings.agents[index].displayName)
                                .textFieldStyle(.roundedBorder)
                            TextField("Check Name Pattern", text: $settings.agents[index].checkNamePattern)
                                .textFieldStyle(.roundedBorder)
                            TextField("Comment Author Login", text: $settings.agents[index].commentAuthor)
                                .textFieldStyle(.roundedBorder)
                            Text("Agents match GitHub check runs and comment authors.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Select an agent to edit details.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(20)
    }

    private var selectedAgentIndex: Int? {
        guard let selected = selectedAgents.first else { return nil }
        return settings.agents.firstIndex { $0.id == selected }
    }

    private func addAgent() {
        let agent = AgentConfig(displayName: "New Agent", checkNamePattern: "", commentAuthor: "")
        settings.agents.append(agent)
        selectedAgents = [agent.id]
    }

    private func removeSelectedAgents() {
        let ids = selectedAgents
        settings.agents.removeAll { ids.contains($0.id) }
        selectedAgents.removeAll()
    }

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

private struct StatusBadge: View {
    let isActive: Bool
    let activeText: String
    let inactiveText: String

    var body: some View {
        Text(isActive ? activeText : inactiveText)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background((isActive ? Color.green : Color.gray).opacity(0.18), in: Capsule())
            .foregroundStyle(isActive ? Color.green : Color.gray)
    }
}

private func emptyState(title: String, message: String, systemImage: String) -> some View {
    VStack(spacing: 8) {
        Label(title, systemImage: systemImage)
            .font(.headline)
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, minHeight: 120)
}
