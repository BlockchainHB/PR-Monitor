import Foundation

struct RepoConfig: Identifiable, Codable, Hashable {
    var owner: String
    var name: String
    var isEnabled: Bool

    var id: String { "\(owner)/\(name)" }
    var fullName: String { "\(owner)/\(name)" }
}

struct AgentConfig: Identifiable, Codable, Hashable {
    var id: UUID
    var displayName: String
    var checkNamePattern: String
    var commentAuthor: String

    init(id: UUID = UUID(), displayName: String, checkNamePattern: String, commentAuthor: String) {
        self.id = id
        self.displayName = displayName
        self.checkNamePattern = checkNamePattern
        self.commentAuthor = commentAuthor
    }
}

enum AgentRunStatus: String {
    case running
    case waitingForComment
    case done
    case notFound
}

struct AgentRun: Identifiable, Hashable {
    var id: String
    var displayName: String
    var status: AgentRunStatus
    var commentCount: Int
    var checkConclusion: String?
}

struct PRItem: Identifiable, Hashable {
    var id: Int
    var number: Int
    var title: String
    var author: String
    var updatedAt: Date
    var url: URL
    var repoFullName: String
    var agents: [AgentRun]
}

struct RepoSection: Identifiable, Hashable {
    var id: String { fullName }
    var fullName: String
    var prs: [PRItem]
}
