import Foundation

/// The derived state of one agent on one pull request.
struct AgentReport: Identifiable, Hashable, Sendable {
    enum State: Hashable, Sendable {
        case running
        case failed
        /// Finished, and left feedback someone has to address.
        case needsReview
        case passed
    }

    let id: String
    let name: String
    let state: State
    /// A short, human-readable explanation ("2 of 5 failed", "3 open threads").
    let summary: String
    let openThreads: Int
    let finishedAt: Date?
    let url: URL?
}

/// The overall state of a pull request, derived from its agents.
enum PullRequestStatus: Hashable, Sendable {
    case failing
    case running
    case needsReview
    case ready
    /// No agent has reported anything on the head commit.
    case quiet

    /// How urgently this status wants the user's attention when summarizing many PRs.
    var urgency: Int {
        switch self {
        case .failing: 4
        case .needsReview: 3
        case .running: 2
        case .ready: 1
        case .quiet: 0
        }
    }

    var needsAttention: Bool { self == .failing || self == .needsReview }
}

struct PullRequestReport: Identifiable, Hashable, Sendable {
    let pullRequest: PullRequest
    let agents: [AgentReport]
    let status: PullRequestStatus

    var id: String { pullRequest.id }
    /// True once no agent is still working. This is the moment the app exists to announce.
    var isSettled: Bool { !agents.contains { $0.state == .running } }
    var finishedAgentCount: Int { agents.count { $0.state != .running } }
    var openThreadCount: Int { pullRequest.threads.count(where: \.isOpen) }
}

/// Reduces the raw signals on a pull request into per-agent and overall status.
///
/// Pure and deterministic: the same inputs and `now` always produce the same report.
struct StatusEngine: Sendable {
    var mode: AgentMode
    var agents: [Agent]
    /// How long after a push a configured agent that hasn't reported yet is assumed to be starting,
    /// rather than not applicable to this PR.
    var startupGracePeriod: TimeInterval = 180

    func report(for pr: PullRequest, now: Date = .now) -> PullRequestReport {
        var reports: [AgentReport] = switch mode {
        case .automatic: automaticReports(for: pr, now: now)
        case .custom: agents.filter(\.isValid).compactMap { configuredReport(for: $0, pr: pr, now: now) }
        }
        // Trust GitHub's roll-up over our own reading when they disagree: a pending roll-up with no
        // pending check in view means something we can't see (>100 checks, a queued suite) is running.
        if mode == .automatic, pr.rollupState == "PENDING" || pr.rollupState == "EXPECTED",
           !pr.checks.contains(where: { $0.outcome == .pending }) {
            reports.append(AgentReport(id: "rollup", name: "Other checks", state: .running, summary: "In progress",
                                       openThreads: 0, finishedAt: nil, url: pr.checksURL))
        }
        return PullRequestReport(pullRequest: pr, agents: reports, status: status(of: reports, pr: pr))
    }

    // MARK: - Overall status

    private func status(of agents: [AgentReport], pr: PullRequest) -> PullRequestStatus {
        guard !agents.isEmpty else { return .quiet }
        // A failure is actionable immediately, even while other agents are still working.
        if agents.contains(where: { $0.state == .failed }) { return .failing }
        if agents.contains(where: { $0.state == .running }) { return .running }
        if agents.contains(where: { $0.state == .needsReview }) || pr.reviewDecision == .changesRequested {
            return .needsReview
        }
        return .ready
    }

    // MARK: - Automatic mode

    /// Every check integration and review bot on the PR becomes an agent. Signals from the same
    /// integration are grouped: all GitHub Actions jobs form one agent, and a bot's commit status,
    /// check run and review threads merge when its login matches the app slug.
    private func automaticReports(for pr: PullRequest, now: Date) -> [AgentReport] {
        var names: [String: String] = [:]
        var order: [String] = []
        func register(_ key: String, name: @autoclosure () -> String) {
            guard !key.isEmpty, names[key] == nil else { return }
            names[key] = name()
            order.append(key)
        }

        for check in pr.checks { register(check.groupKey, name: check.groupDisplayName) }
        // Bots that participate in review. Comment-only bots (changeset, codecov…) are left out:
        // they have no lifecycle, so they would only add noise.
        let reviewBots = pr.requestedReviewers.filter(\.isBot).map(\.login)
            + pr.reviews.filter(\.isBot).map(\.author)
            + pr.threads.filter(\.isBot).map(\.author)
        for login in reviewBots { register(Identity.normalize(login), name: Self.displayName(forLogin: login)) }

        return order.compactMap { key in
            evaluate(
                id: key,
                name: names[key] ?? key,
                checks: pr.checks.filter { $0.groupKey == key },
                pr: pr,
                login: key,
                isConfigured: false,
                now: now
            )
        }
    }

    // MARK: - Custom mode

    private func configuredReport(for agent: Agent, pr: PullRequest, now: Date) -> AgentReport? {
        let pattern = Identity.normalize(agent.checkPattern)
        let login = Identity.normalize(agent.login)
        let checks = pr.checks.filter { check in
            if !pattern.isEmpty, check.searchableFields.contains(where: { Identity.normalize($0).contains(pattern) }) {
                return true
            }
            return !login.isEmpty && check.groupKey == login
        }
        return evaluate(
            id: agent.id.uuidString,
            name: agent.name,
            checks: checks,
            pr: pr,
            login: login,
            isConfigured: true,
            now: now
        )
    }

    // MARK: - Evaluation

    /// - Parameter login: normalized login used to attribute reviews, threads and comments.
    private func evaluate(
        id: String,
        name: String,
        checks: [CheckSignal],
        pr: PullRequest,
        login: String,
        isConfigured: Bool,
        now: Date
    ) -> AgentReport? {
        let byAgent: (String) -> Bool = { !login.isEmpty && Identity.normalize($0) == login }
        let isRequested = pr.requestedReviewers.contains { byAgent($0.login) }
        let latestReview = pr.reviews.filter { byAgent($0.author) }
            .max { ($0.submittedAt ?? .distantPast) < ($1.submittedAt ?? .distantPast) }
        let threads = pr.threads.filter { byAgent($0.author) }
        let openThreads = threads.count(where: \.isOpen)
        let headDate = pr.headCommittedAt ?? .distantPast
        let recentComments = pr.comments.filter { byAgent($0.author) && $0.createdAt >= headDate }
        let isWithinStartup = pr.headCommittedAt.map { now.timeIntervalSince($0) < startupGracePeriod } ?? false

        let hasActivity = !checks.isEmpty || isRequested || latestReview != nil || !threads.isEmpty || !recentComments.isEmpty
        guard hasActivity else {
            // A configured agent that hasn't reported right after a push is probably still starting.
            // After the grace period it's treated as not applicable to this PR and hidden.
            guard isConfigured, isWithinStartup else { return nil }
            return AgentReport(id: id, name: name, state: .running, summary: "Waiting to start",
                               openThreads: 0, finishedAt: nil, url: nil)
        }

        let failed = checks.filter { $0.outcome == .failed }
        let pending = checks.filter { $0.outcome == .pending }
        let finishedAt = (checks.compactMap(\.completedAt) + [latestReview?.submittedAt].compactMap(\.self)).max()
        let primaryURL = (failed.first ?? pending.first ?? checks.first)?.url

        func report(_ state: AgentReport.State, _ summary: String, finished: Date? = nil) -> AgentReport {
            AgentReport(id: id, name: name, state: state, summary: summary, openThreads: openThreads,
                        finishedAt: finished, url: primaryURL)
        }

        if !failed.isEmpty {
            let summary = checks.count == 1 ? Self.label(forRawState: failed[0].rawState) : "\(failed.count) of \(checks.count) failed"
            return report(.failed, summary, finished: finishedAt)
        }
        if !pending.isEmpty {
            let summary: String
            if checks.count > 1 {
                summary = "\(checks.count - pending.count) of \(checks.count) complete"
            } else {
                summary = pending[0].startedAt == nil ? "Queued" : "In progress"
            }
            return report(.running, summary)
        }
        if isRequested {
            return report(.running, "Reviewing")
        }
        if openThreads > 0 {
            return report(.needsReview, openThreads == 1 ? "1 open thread" : "\(openThreads) open threads", finished: finishedAt)
        }
        if latestReview?.state == .changesRequested {
            return report(.needsReview, "Changes requested", finished: finishedAt)
        }

        // Review-only agents (no checks) re-review on push without announcing it. A review of an
        // older commit is stale: briefly assume a new one is coming.
        if checks.isEmpty, let latestReview, Self.isStale(latestReview, on: pr) {
            if isWithinStartup { return report(.running, "Waiting to review") }
            return report(.passed, "Reviewed an earlier commit", finished: finishedAt)
        }

        let summary: String
        if checks.isEmpty {
            summary = switch latestReview?.state {
            case .approved: "Approved"
            case .some: "Reviewed"
            case nil: "Commented"
            }
        } else if checks.allSatisfy({ $0.outcome == .neutral }) {
            summary = checks.count == 1 ? Self.label(forRawState: checks[0].rawState) : "Skipped"
        } else {
            summary = checks.count == 1 ? "Passed" : "\(checks.count) checks passed"
        }
        return report(.passed, summary, finished: finishedAt)
    }

    private static func isStale(_ review: ReviewSignal, on pr: PullRequest) -> Bool {
        if let sha = review.commitSHA { return sha != pr.headSHA }
        guard let submitted = review.submittedAt, let committed = pr.headCommittedAt else { return false }
        return submitted < committed
    }

    // MARK: - Formatting

    static func label(forRawState raw: String) -> String {
        switch raw.uppercased() {
        case "SUCCESS": "Passed"
        case "FAILURE": "Failed"
        case "ERROR": "Errored"
        case "TIMED_OUT": "Timed out"
        case "ACTION_REQUIRED": "Action required"
        case "STARTUP_FAILURE": "Failed to start"
        case "CANCELLED": "Cancelled"
        case "SKIPPED": "Skipped"
        case "NEUTRAL": "Neutral"
        case "STALE": "Stale"
        default: raw.replacing("_", with: " ").capitalized
        }
    }

    static func displayName(forLogin login: String) -> String {
        if let preset = Agent.presetName(forKey: login) { return preset }
        let base = login.replacing("[bot]", with: "")
        return base.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
