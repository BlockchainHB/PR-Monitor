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

    private var reposTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Manual Entry Section
                SettingsSection(icon: "plus.square", title: "Add Repository", description: "Enter repository in owner/name format") {
                    HStack(spacing: 12) {
                        HStack {
                            Image(systemName: "number")
                                .foregroundColor(.secondary)
                                .frame(width: 20)
                            TextField("owner/name", text: $newRepoText)
                                .textFieldStyle(.plain)
                        }
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                        
                        Button {
                            if settings.addRepo(from: newRepoText) != nil {
                                newRepoText = ""
                            }
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newRepoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                // Tracked Repos Section
                SettingsSection(icon: "folder.badge.gearshape", title: "Tracked Repositories", description: "Repositories being monitored for pull requests") {
                    if settings.repos.isEmpty {
                        EmptyStateView(
                            icon: "folder.badge.questionmark",
                            message: "No repositories tracked yet",
                            hint: "Add repositories manually or fetch from GitHub"
                        )
                        .padding(.vertical, 20)
                    } else {
                        VStack(spacing: 8) {
                            ForEach($settings.repos) { $repo in
                                HStack(spacing: 12) {
                                    Image(systemName: repo.isEnabled ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(repo.isEnabled ? .green : .secondary)
                                        .imageScale(.large)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(repo.fullName)
                                            .font(.body)
                                        Text(repo.isEnabled ? "Monitoring active" : "Disabled")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Toggle("", isOn: $repo.isEnabled)
                                        .labelsHidden()
                                        .toggleStyle(.switch)
                                    
                                    Button {
                                        settings.repos.removeAll { $0.id == repo.id }
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove repository")
                                }
                                .padding(12)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(8)
                            }
                        }
                    }
                }

                Divider()
                    .padding(.vertical, 8)

                // GitHub Repos Section
                SettingsSection(
                    icon: "cloud",
                    title: "Browse GitHub Repositories",
                    description: "Fetch and add repositories from your GitHub account"
                ) {
                    HStack(spacing: 12) {
                        Button {
                            loadRepos()
                        } label: {
                            Label(isLoadingRepos ? "Loading..." : "Fetch My Repos", systemImage: isLoadingRepos ? "arrow.clockwise" : "arrow.down.circle")
                        }
                        .disabled(isLoadingRepos || !authStore.isSignedIn)
                        
                        if !authStore.isSignedIn {
                            Text("Sign in required")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(4)
                        }
                        
                        Spacer()
                    }

                    if let error = repoLoadError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                    }

                    if !availableRepos.isEmpty {
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                TextField("Filter repositories", text: $repoSearch)
                                    .textFieldStyle(.plain)
                                if !repoSearch.isEmpty {
                                    Button {
                                        repoSearch = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(8)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)
                            
                            ScrollView {
                                VStack(spacing: 6) {
                                    ForEach(filteredAvailableRepos) { repo in
                                        HStack(spacing: 12) {
                                            Image(systemName: repo.isPrivate ? "lock.fill" : "globe")
                                                .foregroundColor(repo.isPrivate ? .orange : .blue)
                                                .frame(width: 20)
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(repo.fullName)
                                                    .font(.body)
                                                if repo.isPrivate {
                                                    Text("Private")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            
                                            Spacer()
                                            
                                            Toggle("", isOn: bindingForRepo(repo))
                                                .labelsHidden()
                                                .toggleStyle(.switch)
                                        }
                                        .padding(10)
                                        .background(Color(nsColor: .controlBackgroundColor))
                                        .cornerRadius(6)
                                    }
                                }
                            }
                            .frame(maxHeight: 200)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var agentsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Info Section
                SettingsSection(
                    icon: "info.circle",
                    title: "About Agents",
                    description: "Agents are CI/CD tools that run checks and post comments on pull requests. Configure them by mapping display names to check patterns and comment authors."
                ) {
                    EmptyView()
                }

                // Auto-detect Section
                SettingsSection(icon: "wand.and.stars", title: "Auto-Discovery", description: "Automatically find agents from your open pull requests") {
                    HStack(spacing: 12) {
                        Button {
                            detectAgents()
                        } label: {
                            Label(isDetectingAgents ? "Detecting..." : "Scan Open PRs", systemImage: isDetectingAgents ? "arrow.clockwise" : "sparkles")
                        }
                        .disabled(isDetectingAgents || !authStore.isSignedIn || settings.enabledRepos.isEmpty)
                        
                        if settings.enabledRepos.isEmpty {
                            Text("Enable repos first")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(4)
                        }
                        
                        Spacer()
                    }

                    if let error = agentDetectError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                    }
                }

                // Add Agent Section
                SettingsSection(icon: "plus.square", title: "Add Agent Manually", description: "Create a custom agent configuration") {
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Display Name")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack {
                                    Image(systemName: "tag")
                                        .foregroundColor(.secondary)
                                        .frame(width: 20)
                                    TextField("e.g., CodeReview Bot", text: $newAgentName)
                                        .textFieldStyle(.plain)
                                }
                                .padding(8)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(6)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Check Name Pattern")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack {
                                    Image(systemName: "checklist")
                                        .foregroundColor(.secondary)
                                        .frame(width: 20)
                                    TextField("e.g., review-bot", text: $newAgentCheckPattern)
                                        .textFieldStyle(.plain)
                                }
                                .padding(8)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(6)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Comment Author")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack {
                                    Image(systemName: "person")
                                        .foregroundColor(.secondary)
                                        .frame(width: 20)
                                    TextField("e.g., review-bot[bot]", text: $newAgentCommentAuthor)
                                        .textFieldStyle(.plain)
                                }
                                .padding(8)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(6)
                            }
                        }
                        
                        Button {
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
                        } label: {
                            Label("Add Agent", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newAgentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

                // Configured Agents Section
                SettingsSection(icon: "cpu", title: "Configured Agents", description: "Manage your agent configurations") {
                    if settings.agents.isEmpty {
                        EmptyStateView(
                            icon: "cpu.slash",
                            message: "No agents configured",
                            hint: "Add agents manually or use auto-discovery"
                        )
                        .padding(.vertical, 20)
                    } else {
                        VStack(spacing: 10) {
                            ForEach($settings.agents) { $agent in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Image(systemName: "cpu")
                                            .foregroundColor(.blue)
                                            .imageScale(.large)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Display Name")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            TextField("Display name", text: $agent.displayName)
                                                .textFieldStyle(.plain)
                                                .font(.body)
                                        }
                                        
                                        Spacer()
                                        
                                        Button {
                                            settings.agents.removeAll { $0.id == agent.id }
                                        } label: {
                                            Image(systemName: "trash")
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Remove agent")
                                    }
                                    
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Image(systemName: "checklist")
                                                    .foregroundColor(.secondary)
                                                    .font(.caption)
                                                Text("Check Pattern")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            TextField("Check name pattern", text: $agent.checkNamePattern)
                                                .textFieldStyle(.plain)
                                                .font(.callout)
                                        }
                                        .padding(8)
                                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                                        .cornerRadius(6)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Image(systemName: "person")
                                                    .foregroundColor(.secondary)
                                                    .font(.caption)
                                                Text("Author Login")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            TextField("Comment author", text: $agent.commentAuthor)
                                                .textFieldStyle(.plain)
                                                .font(.callout)
                                        }
                                        .padding(8)
                                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                                        .cornerRadius(6)
                                    }
                                }
                                .padding(14)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var authTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // OAuth Configuration Section
                SettingsSection(icon: "key.horizontal", title: "GitHub OAuth Configuration", description: "Configure your GitHub OAuth application credentials") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("OAuth Client ID")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Image(systemName: "lock.shield")
                                .foregroundColor(.secondary)
                                .frame(width: 20)
                            TextField("Enter your GitHub OAuth Client ID", text: $settings.githubClientId)
                                .textFieldStyle(.plain)
                                .font(.system(.body, design: .monospaced))
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                        
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                                .font(.caption)
                            Text("Create an OAuth app at github.com/settings/developers")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Divider()

                // Authentication Status Section
                if authStore.isSignedIn {
                    SettingsSection(icon: "checkmark.circle.fill", title: "Authentication Status", description: "") {
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .foregroundColor(.green)
                                    .font(.system(size: 40))
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Signed In")
                                        .font(.headline)
                                        .foregroundColor(.green)
                                    Text("You're authenticated with GitHub")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                            .padding(14)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                            
                            Button(role: .destructive) {
                                authStore.signOut()
                            } label: {
                                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    SettingsSection(icon: "person.badge.key", title: "GitHub Sign-In", description: "Authenticate with GitHub to monitor your repositories") {
                        VStack(spacing: 12) {
                            Button {
                                authStore.signIn(clientId: settings.githubClientId)
                            } label: {
                                Label(authStore.isSigningIn ? "Signing In..." : "Start Device Sign-In", systemImage: authStore.isSigningIn ? "arrow.clockwise" : "person.badge.plus")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(authStore.isSigningIn || settings.githubClientId.isEmpty)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            if settings.githubClientId.isEmpty {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("Please enter your OAuth Client ID above")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(6)
                            }

                            if let flow = authStore.deviceFlow {
                                VStack(alignment: .leading, spacing: 12) {
                                    Divider()
                                    
                                    HStack(spacing: 12) {
                                        Image(systemName: "qrcode")
                                            .font(.system(size: 40))
                                            .foregroundColor(.blue)
                                        
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Enter this code at GitHub:")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            
                                            Text(flow.userCode)
                                                .font(.system(size: 24, weight: .bold, design: .monospaced))
                                                .foregroundColor(.primary)
                                                .textSelection(.enabled)
                                            
                                            Button {
                                                NSWorkspace.shared.open(flow.verificationURL)
                                            } label: {
                                                HStack {
                                                    Image(systemName: "safari")
                                                    Text("Open GitHub")
                                                }
                                            }
                                            .buttonStyle(.link)
                                        }
                                    }
                                    .padding(14)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(8)
                                }
                            }
                        }
                    }
                }

                if let message = authStore.statusMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var notificationsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection(icon: "bell.badge", title: "Notification Preferences", description: "Configure when you want to be notified about PR status changes") {
                    VStack(spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.title2)
                                .frame(width: 40)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("All Agents Complete")
                                    .font(.body)
                                Text("Get notified when all agents finish running on a PR")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: .constant(true))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .disabled(true)
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                        
                        HStack(spacing: 12) {
                            Image(systemName: "bell.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title2)
                                .frame(width: 40)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Per-Agent Notifications")
                                    .font(.body)
                                Text("Get notified as each individual agent completes")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: $settings.notifyPerAgent)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                
                SettingsSection(icon: "info.circle", title: "About Notifications", description: "") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("System notifications will appear when enabled")
                                    .font(.caption)
                                Text("Make sure to allow notifications in System Settings")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "clock")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Notifications are sent only once per status change")
                                    .font(.caption)
                                Text("You won't receive duplicate notifications for the same event")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(8)
                }
                
                Spacer()
            }
            .padding(.vertical, 4)
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
// MARK: - Helper Views

private struct SettingsSection<Content: View>: View {
    let icon: String
    let title: String
    let description: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                    .imageScale(.medium)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    if !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            content
        }
    }
}

private struct EmptyStateView: View {
    let icon: String
    let message: String
    let hint: String
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
            
            Text(hint)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }
}

