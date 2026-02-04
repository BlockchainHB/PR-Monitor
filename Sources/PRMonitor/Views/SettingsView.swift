import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var authStore: AuthStore

    @State private var newRepoText = ""
    @State private var repoSearch = ""
    @State private var availableRepos: [RepoDTO] = []
    @State private var isLoadingRepos = false
    @State private var repoLoadError: String?
    @State private var newAgentName = ""
    @State private var newAgentCheckPattern = ""
    @State private var newAgentCommentAuthor = ""
    @State private var isDetectingAgents = false
    @State private var agentDetectError: String?

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            reposTab
                .tabItem {
                    Label("Repositories", systemImage: "folder")
                }
            agentsTab
                .tabItem {
                    Label("Agents", systemImage: "cpu")
                }
            authTab
                .tabItem {
                    Label("Authentication", systemImage: "key")
                }
            notificationsTab
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
        }
        .padding(20)
        .frame(width: 600, height: 500)
    }

    private var generalTab: some View {
        Form {
            Section {
                Picker("Polling Interval", selection: $settings.pollingIntervalSeconds) {
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                    Text("5 minutes").tag(300)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Refresh")
            } footer: {
                Text("When no open PRs are found, refreshes every 10 minutes.")
            }
        }
        .formStyle(.grouped)
    }

    private var reposTab: some View {
        Form {
            Section {
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
            } header: {
                Text("Add Repository")
            }

            Section {
                if settings.repos.isEmpty {
                    Text("No repositories added")
                        .foregroundColor(.secondary)
                } else {
                    List {
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
                    .frame(height: 150)
                }
            } header: {
                Text("Tracked Repositories")
            }

            Section {
                Button {
                    loadRepos()
                } label: {
                    if isLoadingRepos {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Fetching repositories...")
                        }
                    } else {
                        Label("Fetch from GitHub", systemImage: "arrow.down.circle")
                    }
                }
                .disabled(isLoadingRepos || !authStore.isSignedIn)
                
                if !authStore.isSignedIn {
                    Text("Sign in required")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let error = repoLoadError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
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
            
            if !availableRepos.isEmpty {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search repositories", text: $repoSearch)
                            .textFieldStyle(.roundedBorder)
                        if !repoSearch.isEmpty {
                            Button {
                                repoSearch = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("Filter")
                }
                
                Section {
                    List {
                        ForEach(filteredAvailableRepos) { repo in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(repo.fullName)
                                    if repo.isPrivate {
                                        HStack(spacing: 4) {
                                            Image(systemName: "lock.fill")
                                                .font(.caption2)
                                            Text("Private")
                                                .font(.caption2)
                                        }
                                        .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Toggle("", isOn: bindingForRepo(repo))
                                    .labelsHidden()
                            }
                        }
                    }
                    .listStyle(.inset)
                    .frame(height: 220)
                } header: {
                    Text("Available Repositories")
                } footer: {
                    if !repoSearch.isEmpty {
                        Text("Showing \(filteredAvailableRepos.count) of \(availableRepos.count) repositories")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var agentsTab: some View {
        Form {
            Section {
                Button {
                    detectAgents()
                } label: {
                    if isDetectingAgents {
                        HStack(spacing: 8) {
                            ProgressView()
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
                        .foregroundColor(.red)
                } else if settings.enabledRepos.isEmpty {
                    Text("Enable repositories first")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Quick Setup")
            } footer: {
                Text("Automatically find agents from your pull requests")
            }

            if settings.agents.isEmpty {
                Section {
                    Text("No agents configured yet")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } header: {
                    Text("Configured Agents")
                } footer: {
                    Text("Each agent monitors specific checks and comments on PRs")
                }
            } else {
                Section {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach($settings.agents) { $agent in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(agent.displayName.isEmpty ? "Unnamed Agent" : agent.displayName)
                                            .font(.headline)
                                        Spacer()
                                        Button {
                                            settings.agents.removeAll { $0.id == agent.id }
                                        } label: {
                                            Image(systemName: "trash")
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                    
                                    Divider()
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Display Name")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        TextField("e.g., Code Review Bot", text: $agent.displayName)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Check Name Pattern")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        TextField("e.g., review-bot or CI/Test", text: $agent.checkNamePattern)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Comment Author Login")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        TextField("e.g., review-bot[bot]", text: $agent.commentAuthor)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                }
                                .padding(12)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(height: 240)
                } header: {
                    Text("Configured Agents")
                } footer: {
                    Text("Each agent monitors specific checks and comments on PRs")
                        .padding(.top, 4)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Display Name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("e.g., Code Review Bot", text: $newAgentName)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Check Name Pattern")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("e.g., review-bot or CI/Test", text: $newAgentCheckPattern)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Comment Author Login")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("e.g., review-bot[bot]", text: $newAgentCommentAuthor)
                            .textFieldStyle(.roundedBorder)
                    }
                    
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
                }
            } header: {
                Text("Add New Agent")
            } footer: {
                Text("Agents match GitHub check runs and comment authors")
            }
        }
        .formStyle(.grouped)
    }

    private var authTab: some View {
        Form {
            Section {
                TextField("Client ID", text: $settings.githubClientId)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
            } header: {
                Text("GitHub OAuth")
            } footer: {
                Text("Create an OAuth app at github.com/settings/developers")
            }

            Section {
                if authStore.isSignedIn {
                    Text("✓ Signed In")
                        .foregroundColor(.green)
                    Button("Sign Out") {
                        authStore.signOut()
                    }
                } else {
                    Button(authStore.isSigningIn ? "Signing In..." : "Sign In with Device Code") {
                        authStore.signIn(clientId: settings.githubClientId)
                    }
                    .disabled(authStore.isSigningIn || settings.githubClientId.isEmpty)

                    if let flow = authStore.deviceFlow {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Enter this code at GitHub:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(flow.userCode)
                                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                                .textSelection(.enabled)
                            Button {
                                NSWorkspace.shared.open(flow.verificationURL)
                            } label: {
                                Text("Open GitHub")
                            }
                        }
                    }
                }

                if let message = authStore.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Authentication")
            }
        }
        .formStyle(.grouped)
    }

    private var notificationsTab: some View {
        Form {
            Section {
                Toggle("All agents complete", isOn: .constant(true))
                    .disabled(true)
                Toggle("Per-agent completion", isOn: $settings.notifyPerAgent)
            } header: {
                Text("Notifications")
            } footer: {
                Text("Receive notifications when agent checks complete on your PRs")
            }
        }
        .formStyle(.grouped)
    }

    private var filteredAvailableRepos: [RepoDTO] {
        let trimmed = repoSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return availableRepos }
        return availableRepos.filter { $0.fullName.localizedCaseInsensitiveContains(trimmed) }
    }

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
