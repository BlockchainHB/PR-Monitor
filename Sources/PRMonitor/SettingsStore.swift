import Foundation

final class SettingsStore: ObservableObject {
    @Published var repos: [RepoConfig] = [] {
        didSet { save() }
    }
    @Published var agents: [AgentConfig] = [] {
        didSet { save() }
    }
    @Published var pollingIntervalSeconds: Int = 60 {
        didSet { save() }
    }
    @Published var notifyPerAgent: Bool = false {
        didSet { save() }
    }
    @Published var notifySummary: Bool = true {
        didSet { save() }
    }
    @Published var githubClientId: String = "" {
        didSet { save() }
    }

    private let storageKey = "PRMonitorSettings"

    init() {
        load()
        if repos.isEmpty {
            repos = []
        }
        if agents.isEmpty {
            agents = [
                AgentConfig(displayName: "Vercel", checkNamePattern: "vercel", commentAuthor: "vercel"),
                AgentConfig(displayName: "Cursor Bugbot", checkNamePattern: "cursor", commentAuthor: "cursor"),
                AgentConfig(displayName: "Devin Review", checkNamePattern: "devin", commentAuthor: "devin-ai-integration")
            ]
        }
    }

    var enabledRepos: [RepoConfig] {
        repos.filter { $0.isEnabled }
    }

    func addRepo(from text: String) -> RepoConfig? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: "/").map(String.init)
        guard parts.count == 2 else { return nil }
        let owner = parts[0]
        let name = parts[1]
        guard !owner.isEmpty, !name.isEmpty else { return nil }
        let repo = RepoConfig(owner: owner, name: name, isEnabled: true)
        if !repos.contains(where: { $0.id == repo.id }) {
            repos.append(repo)
        }
        return repo
    }

    func setRepoEnabled(owner: String, name: String, enabled: Bool) {
        let repoId = "\(owner)/\(name)"
        if let index = repos.firstIndex(where: { $0.id == repoId }) {
            repos[index].isEnabled = enabled
        } else if enabled {
            repos.append(RepoConfig(owner: owner, name: name, isEnabled: true))
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            let decoded = try JSONDecoder().decode(PersistedSettings.self, from: data)
            repos = decoded.repos
            agents = decoded.agents
            pollingIntervalSeconds = decoded.pollingIntervalSeconds
            notifyPerAgent = decoded.notifyPerAgent
            notifySummary = decoded.notifySummary
            githubClientId = decoded.githubClientId
        } catch {
            repos = []
            agents = []
            pollingIntervalSeconds = 60
            notifyPerAgent = false
            notifySummary = true
            githubClientId = ""
        }
    }

    private func save() {
        let payload = PersistedSettings(
            repos: repos,
            agents: agents,
            pollingIntervalSeconds: pollingIntervalSeconds,
            notifyPerAgent: notifyPerAgent,
            notifySummary: notifySummary,
            githubClientId: githubClientId
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

private struct PersistedSettings: Codable {
    var repos: [RepoConfig]
    var agents: [AgentConfig]
    var pollingIntervalSeconds: Int
    var notifyPerAgent: Bool
    var notifySummary: Bool
    var githubClientId: String

    enum CodingKeys: String, CodingKey {
        case repos
        case agents
        case pollingIntervalSeconds
        case notifyPerAgent
        case notifySummary
        case githubClientId
    }

    init(repos: [RepoConfig], agents: [AgentConfig], pollingIntervalSeconds: Int, notifyPerAgent: Bool, notifySummary: Bool, githubClientId: String) {
        self.repos = repos
        self.agents = agents
        self.pollingIntervalSeconds = pollingIntervalSeconds
        self.notifyPerAgent = notifyPerAgent
        self.notifySummary = notifySummary
        self.githubClientId = githubClientId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        repos = try container.decodeIfPresent([RepoConfig].self, forKey: .repos) ?? []
        agents = try container.decodeIfPresent([AgentConfig].self, forKey: .agents) ?? []
        pollingIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .pollingIntervalSeconds) ?? 60
        notifyPerAgent = try container.decodeIfPresent(Bool.self, forKey: .notifyPerAgent) ?? false
        notifySummary = try container.decodeIfPresent(Bool.self, forKey: .notifySummary) ?? true
        githubClientId = try container.decodeIfPresent(String.self, forKey: .githubClientId) ?? ""
    }
}
