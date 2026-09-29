import Foundation

/// Everything the app knows about one open pull request, as reported by GitHub.
///
/// This is deliberately a plain value with no GitHub DTO types in it: the GitHub layer maps its
/// responses into this shape, and everything downstream (status derivation, notifications, UI) is
/// pure and testable against hand-built values.
struct PullRequest: Identifiable, Hashable, Sendable {
    /// GraphQL node ID; stable across polls.
    let id: String
    let repository: RepositoryID
    let number: Int
    let title: String
    let url: URL
    let author: String?
    let isDraft: Bool
    let createdAt: Date
    let updatedAt: Date
    let headSHA: String
    let headCommittedAt: Date?
    /// GitHub's own roll-up of every check on the head commit. Used as a safety net: it also
    /// counts checks the detail query can't see (more than 100, or suites without runs yet).
    let rollupState: String?
    let reviewDecision: ReviewDecision?
    let mergeable: Mergeable

    let checks: [CheckSignal]
    let requestedReviewers: [ReviewRequestSignal]
    let reviews: [ReviewSignal]
    let threads: [ThreadSignal]
    let comments: [CommentSignal]

    var key: PullRequestKey { PullRequestKey(repository: repository, number: number) }
    var checksURL: URL { url.appending(path: "checks") }
}

/// A human-readable identity for a PR (`owner/name#123`), used for notification bookkeeping.
struct PullRequestKey: Hashable, Codable, Sendable, CustomStringConvertible {
    let repository: RepositoryID
    let number: Int
    var description: String { "\(repository.fullName)#\(number)" }
}

enum ReviewDecision: String, Sendable, Hashable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case reviewRequired = "REVIEW_REQUIRED"
}

enum Mergeable: String, Sendable, Hashable {
    case mergeable = "MERGEABLE"
    case conflicting = "CONFLICTING"
    case unknown = "UNKNOWN"
}

/// One check run or commit status on the head commit.
struct CheckSignal: Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case checkRun(appName: String?, appSlug: String?)
        case commitStatus(creator: String?)
    }

    enum Outcome: Hashable, Sendable {
        case pending
        case succeeded
        /// Completed without passing or failing: skipped, neutral, cancelled or stale.
        case neutral
        case failed
    }

    let name: String
    let source: Source
    let outcome: Outcome
    /// GitHub's raw status or conclusion (e.g. `TIMED_OUT`), kept for display.
    let rawState: String
    let startedAt: Date?
    let completedAt: Date?
    let url: URL?

    /// The key that groups related signals into one automatic agent: the app slug for check runs
    /// (all GitHub Actions jobs become one agent) and the creator for statuses. This is also what
    /// merges Vercel's commit status and its "Preview Comments" check run into a single row.
    var groupKey: String {
        switch source {
        case let .checkRun(appName, appSlug): Identity.normalize(appSlug ?? appName ?? name)
        case let .commitStatus(creator): Identity.normalize(creator ?? name)
        }
    }

    var groupDisplayName: String {
        switch source {
        case let .checkRun(appName, appSlug): Agent.presetName(forKey: appSlug ?? "") ?? appName ?? name
        case let .commitStatus(creator): Agent.presetName(forKey: creator ?? "") ?? name
        }
    }

    /// Strings a user-entered check pattern is matched against.
    var searchableFields: [String] {
        switch source {
        case let .checkRun(appName, appSlug): [name, appName, appSlug].compactMap(\.self)
        case let .commitStatus(creator): [name, creator].compactMap(\.self)
        }
    }
}

/// A pending review request. GitHub removes the request once the reviewer submits, so a request
/// that is still present means that reviewer hasn't finished.
struct ReviewRequestSignal: Hashable, Sendable {
    let login: String
    let isBot: Bool
}

struct ReviewSignal: Hashable, Sendable {
    enum State: String, Sendable {
        case approved = "APPROVED"
        case changesRequested = "CHANGES_REQUESTED"
        case commented = "COMMENTED"
        case dismissed = "DISMISSED"
        case pending = "PENDING"
    }

    let author: String
    let isBot: Bool
    let state: State
    let submittedAt: Date?
    /// The commit the review was left on, so a review of an older push can be told apart.
    let commitSHA: String?
}

struct ThreadSignal: Hashable, Sendable {
    let author: String
    let isBot: Bool
    let isResolved: Bool
    let isOutdated: Bool
    let createdAt: Date?

    /// An unresolved thread on current code: the strongest signal that someone needs to act.
    var isOpen: Bool { !isResolved && !isOutdated }
}

struct CommentSignal: Hashable, Sendable {
    let author: String
    let isBot: Bool
    let createdAt: Date
}
