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
            reposTab
                .tabItem {
                    Label("Repos", systemImage: "folder.badge.gearshape")
                }
            agentsTab
                .tabItem {
                    Label("Agents", systemImage: "cpu")
                }
            authTab
                .tabItem {
                    Label("Auth", systemImage: "key.horizontal")
                }
            notificationsTab
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
        }
        .padding(24)
        .frame(width: 700, height: 500)
        .onAppear {
            activateForSettings()
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private var reposTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tracked Repositories")
                .font(.headline)
            HStack {
                TextField("owner/name", text: $newRepoText)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    if settings.addRepo(from: newRepoText) != nil {
                        newRepoText = ""
                    }
                }
            }

            List {
                ForEach($settings.repos) { $repo in
                    HStack {
                        Toggle(repo.fullName, isOn: $repo.isEnabled)
                            .toggleStyle(.checkbox)
                        Spacer()
                        Button(role: .destructive) {
                            settings.repos.removeAll { $0.id == repo.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            HStack {
                Text("GitHub Repos")
                    .font(.headline)
                Spacer()
                Button(isLoadingRepos ? "Loading..." : "Fetch") {
                    loadRepos()
                }
                .disabled(isLoadingRepos || !authStore.isSignedIn)
            }

            if let error = repoLoadError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Image(systemName: "magnifyingglass")
                TextField("Filter repos", text: $repoSearch)
                    .textFieldStyle(.roundedBorder)
            }

            List(filteredAvailableRepos) { repo in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(repo.fullName)
                        if repo.isPrivate {
                            Text("Private")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Toggle("Track", isOn: bindingForRepo(repo))
                        .labelsHidden()
                }
            }
        }
    }

    private var agentsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Agents")
                .font(.headline)
            Text("Map each agent to a check name pattern and comment author login.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Button(isDetectingAgents ? "Detecting..." : "Auto-detect from open PRs") {
                    detectAgents()
                }
                .disabled(isDetectingAgents || !authStore.isSignedIn || settings.enabledRepos.isEmpty)
                Spacer()
                if settings.enabledRepos.isEmpty {
                    Text("Enable repos first")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let error = agentDetectError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                TextField("Display name", text: $newAgentName)
                TextField("Check name contains", text: $newAgentCheckPattern)
                TextField("Comment author login", text: $newAgentCommentAuthor)
                Button("Add") {
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
            }

            List {
                ForEach($settings.agents) { $agent in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Display name", text: $agent.displayName)
                            Button(role: .destructive) {
                                settings.agents.removeAll { $0.id == agent.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                        HStack {
                            TextField("Check name contains", text: $agent.checkNamePattern)
                            TextField("Comment author login", text: $agent.commentAuthor)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var authTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GitHub Authentication")
                .font(.headline)

            HStack {
                Text("OAuth Client ID")
                TextField("Client ID", text: $settings.githubClientId)
                    .textFieldStyle(.roundedBorder)
                    .disabled(false)
            }

            if authStore.isSignedIn {
                Text("Signed in.")
                    .foregroundColor(.secondary)
                Button("Sign Out") {
                    authStore.signOut()
                }
            } else {
                Button(authStore.isSigningIn ? "Signing In..." : "Start Device Sign-In") {
                    authStore.signIn(clientId: settings.githubClientId)
                }
                .disabled(authStore.isSigningIn)

                if let flow = authStore.deviceFlow {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enter this code at GitHub:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(flow.userCode)
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        Text(flow.verificationURL.absoluteString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 6)
                }
            }

            if let message = authStore.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var notificationsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notifications")
                .font(.headline)
            Toggle("Notify when all agents are done", isOn: .constant(true))
                .disabled(true)
            Toggle("Notify per agent", isOn: $settings.notifyPerAgent)
        }
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

    private func activateForSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NSApp.windows.first(where: { $0.isVisible })?.makeKeyAndOrderFront(nil)
        }
    }
}
