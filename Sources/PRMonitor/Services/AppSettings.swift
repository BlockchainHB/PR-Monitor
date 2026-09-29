import Foundation
import Observation

/// User preferences, persisted to `UserDefaults` as one versioned JSON document.
@Observable
@MainActor
final class AppSettings {
    enum Scope: String, Codable, CaseIterable, Sendable {
        case all, authored

        var title: String {
            switch self {
            case .all: "All"
            case .authored: "Mine"
            }
        }
    }

    static let refreshIntervals: [TimeInterval] = [30, 60, 120, 300]

    var repositories: [TrackedRepository] = [] { didSet { save() } }
    var agentMode: AgentMode = .automatic { didSet { save() } }
    var agents: [Agent] = [] { didSet { save() } }
    var refreshInterval: TimeInterval = 60 { didSet { save() } }
    var scope: Scope = .all { didSet { save() } }
    var hidesDrafts = false { didSet { save() } }
    var notifiesWhenSettled = true { didSet { save() } }
    var notifiesOnNewFeedback = true { didSet { save() } }
    var notifiesPerAgent = false { didSet { save() } }
    var showsAttentionCount = true { didSet { save() } }
    /// Off by default: the HIG asks menu bar extras to use template (monochrome) images.
    var usesColoredStatusIcon = false { didSet { save() } }
    /// Overrides the client ID bundled in Info.plist, for people who build from source.
    var oauthClientIDOverride = "" { didSet { save() } }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isLoading = false
    private static let storageKey = "PRMonitorSettings.v2"
    private static let legacyStorageKey = "PRMonitorSettings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Derived

    var enabledRepositories: [RepositoryID] {
        repositories.filter(\.isEnabled).map(\.id)
    }

    var oauthClientID: String {
        let override = oauthClientIDOverride.trimmed
        if !override.isEmpty { return override }
        return (Bundle.main.object(forInfoDictionaryKey: "GitHubOAuthClientID") as? String)?.trimmed ?? ""
    }

    var statusEngine: StatusEngine {
        StatusEngine(mode: agentMode, agents: agents)
    }

    var notificationPreferences: NotificationPreferences {
        NotificationPreferences(
            whenSettled: notifiesWhenSettled,
            whenFeedbackArrives: notifiesOnNewFeedback,
            perAgent: notifiesPerAgent
        )
    }

    // MARK: - Mutations

    @discardableResult
    func track(_ repository: RepositoryID) -> Bool {
        guard !repositories.contains(where: { $0.id == repository }) else { return false }
        repositories.append(TrackedRepository(id: repository))
        repositories.sort { $0.id < $1.id }
        return true
    }

    func untrack(_ repository: RepositoryID) {
        repositories.removeAll { $0.id == repository }
    }

    func isTracking(_ repository: RepositoryID) -> Bool {
        repositories.contains { $0.id == repository }
    }

    // MARK: - Persistence

    private struct Document: Codable {
        var repositories: [TrackedRepository]
        var agentMode: AgentMode
        var agents: [Agent]
        var refreshInterval: TimeInterval
        var scope: Scope
        var hidesDrafts: Bool
        var notifiesWhenSettled: Bool
        var notifiesOnNewFeedback: Bool
        var notifiesPerAgent: Bool
        var showsAttentionCount: Bool
        var usesColoredStatusIcon: Bool?
        var oauthClientIDOverride: String
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }

        if let data = defaults.data(forKey: Self.storageKey),
           let document = try? JSONDecoder().decode(Document.self, from: data) {
            apply(document)
        } else if let data = defaults.data(forKey: Self.legacyStorageKey),
                  let legacy = try? JSONDecoder().decode(LegacyDocument.self, from: data) {
            migrate(legacy)
            isLoading = false
            save()
        }
    }

    private func apply(_ document: Document) {
        repositories = document.repositories
        agentMode = document.agentMode
        agents = document.agents
        refreshInterval = document.refreshInterval
        scope = document.scope
        hidesDrafts = document.hidesDrafts
        notifiesWhenSettled = document.notifiesWhenSettled
        notifiesOnNewFeedback = document.notifiesOnNewFeedback
        notifiesPerAgent = document.notifiesPerAgent
        showsAttentionCount = document.showsAttentionCount
        usesColoredStatusIcon = document.usesColoredStatusIcon ?? false
        oauthClientIDOverride = document.oauthClientIDOverride
    }

    private func save() {
        guard !isLoading else { return }
        let document = Document(
            repositories: repositories, agentMode: agentMode, agents: agents, refreshInterval: refreshInterval,
            scope: scope, hidesDrafts: hidesDrafts, notifiesWhenSettled: notifiesWhenSettled,
            notifiesOnNewFeedback: notifiesOnNewFeedback, notifiesPerAgent: notifiesPerAgent,
            showsAttentionCount: showsAttentionCount, usesColoredStatusIcon: usesColoredStatusIcon,
            oauthClientIDOverride: oauthClientIDOverride
        )
        if let data = try? JSONEncoder().encode(document) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    // MARK: - Migration from 0.x

    private struct LegacyDocument: Decodable {
        struct Repo: Decodable { var owner: String; var name: String; var isEnabled: Bool }
        struct LegacyAgent: Decodable { var displayName: String; var checkNamePattern: String; var commentAuthor: String }
        var repos: [Repo]?
        var agents: [LegacyAgent]?
        var pollingIntervalSeconds: Int?
        var notifyPerAgent: Bool?
        var notifySummary: Bool?
        var githubClientId: String?
    }

    private func migrate(_ legacy: LegacyDocument) {
        repositories = (legacy.repos ?? []).map {
            TrackedRepository(id: RepositoryID(owner: $0.owner, name: $0.name), isEnabled: $0.isEnabled)
        }
        refreshInterval = TimeInterval(legacy.pollingIntervalSeconds ?? 60)
        notifiesPerAgent = legacy.notifyPerAgent ?? false
        notifiesWhenSettled = legacy.notifySummary ?? true
        oauthClientIDOverride = legacy.githubClientId ?? ""

        // 0.x seeded Vercel, Cursor and Devin for everyone. If the list is untouched, automatic
        // mode tracks those and more; if it was customized, keep the user's list.
        let seeded: Set<String> = ["vercel", "cursor", "devin"]
        let legacyAgents = legacy.agents ?? []
        let isUntouched = Set(legacyAgents.map { $0.checkNamePattern.lowercased() }) == seeded && legacyAgents.count == seeded.count
        if legacyAgents.isEmpty || isUntouched {
            agentMode = .automatic
        } else {
            agentMode = .custom
            agents = legacyAgents.map {
                Agent(name: $0.displayName, checkPattern: $0.checkNamePattern, login: $0.commentAuthor)
            }
        }
    }
}
