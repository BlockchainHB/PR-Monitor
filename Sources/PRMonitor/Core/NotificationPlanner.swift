import Foundation

/// A notification the app should post.
struct PlannedNotification: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// Every agent finished on the head commit.
        case settled(PullRequestStatus)
        /// A settled PR got worse without a new push (e.g. a bot left threads after its check passed).
        case regressed(PullRequestStatus)
        case agentFinished(name: String, state: AgentReport.State)
    }

    let kind: Kind
    let key: PullRequestKey
    let headSHA: String
    let title: String
    let subtitle: String
    let body: String
    let url: URL

    /// Deterministic, so re-planning the same event replaces rather than duplicates a banner.
    var identifier: String {
        let suffix = switch kind {
        case let .settled(status): "settled-\(status)"
        case let .regressed(status): "regressed-\(status)"
        case let .agentFinished(name, _): "agent-\(name)"
        }
        return "\(key)@\(headSHA.prefix(12))/\(suffix)"
    }
}

struct NotificationPreferences: Hashable, Sendable {
    var whenSettled = true
    var whenFeedbackArrives = true
    var perAgent = false
}

/// Decides which notifications to post by diffing the previous poll against the current one.
///
/// Rules that keep it quiet:
/// - The first poll only records a baseline, so launching the app never floods Notification Center.
/// - Transitions are tracked per head commit: a push starts a fresh lifecycle, and each lifecycle
///   announces "settled" at most once.
/// - PRs first seen after launch only notify if they were opened after the baseline was taken.
struct NotificationPlanner: Sendable {
    struct Snapshot: Hashable, Sendable {
        let headSHA: String
        let status: PullRequestStatus
        let isSettled: Bool
        let agentStates: [String: AgentReport.State]
    }

    private(set) var snapshots: [PullRequestKey: Snapshot] = [:]
    private(set) var baselineDate: Date?

    mutating func plan(
        for reports: [PullRequestReport],
        preferences: NotificationPreferences,
        now: Date = .now
    ) -> [PlannedNotification] {
        let next = Dictionary(reports.map { ($0.pullRequest.key, Self.snapshot(of: $0)) }, uniquingKeysWith: { a, _ in a })
        defer { snapshots = next }

        guard let baselineDate else {
            self.baselineDate = now
            return []
        }

        var planned: [PlannedNotification] = []
        for report in reports {
            let pr = report.pullRequest
            guard let current = next[pr.key] else { continue }
            let previous = snapshots[pr.key]

            if previous == nil, pr.createdAt < baselineDate {
                continue // Existed before launch but newly visible (e.g. repo just enabled).
            }
            let sameCommit = previous?.headSHA == current.headSHA
            let wasSettled = sameCommit && (previous?.isSettled ?? false)

            if preferences.whenSettled, current.isSettled, !wasSettled, current.status != .quiet {
                planned.append(Self.settledNotification(for: report))
            } else if preferences.whenFeedbackArrives, sameCommit, wasSettled, current.isSettled,
                      let previous, current.status.urgency > previous.status.urgency, current.status.needsAttention {
                planned.append(Self.regressedNotification(for: report))
            }

            if preferences.perAgent {
                // A new push restarts every agent's lifecycle, and an agent we haven't seen before
                // on this commit was, by definition, not finished last time we looked.
                for agent in report.agents where agent.state != .running {
                    let before = sameCommit ? (previous?.agentStates[agent.id] ?? .running) : .running
                    if before == .running {
                        planned.append(Self.agentNotification(agent, report: report))
                    }
                }
            }
        }
        return planned
    }

    private static func snapshot(of report: PullRequestReport) -> Snapshot {
        Snapshot(
            headSHA: report.pullRequest.headSHA,
            status: report.status,
            isSettled: report.isSettled,
            agentStates: Dictionary(report.agents.map { ($0.id, $0.state) }, uniquingKeysWith: { a, _ in a })
        )
    }

    // MARK: - Copy

    private static func settledNotification(for report: PullRequestReport) -> PlannedNotification {
        let pr = report.pullRequest
        let (subtitle, body) = describe(report)
        return PlannedNotification(
            kind: .settled(report.status), key: pr.key, headSHA: pr.headSHA,
            title: "\(pr.repository.name) #\(pr.number)", subtitle: subtitle,
            body: "\(pr.title)\n\(body)", url: pr.url
        )
    }

    private static func regressedNotification(for report: PullRequestReport) -> PlannedNotification {
        let pr = report.pullRequest
        let (subtitle, body) = describe(report)
        return PlannedNotification(
            kind: .regressed(report.status), key: pr.key, headSHA: pr.headSHA,
            title: "\(pr.repository.name) #\(pr.number)", subtitle: subtitle,
            body: "\(pr.title)\n\(body)", url: pr.url
        )
    }

    private static func agentNotification(_ agent: AgentReport, report: PullRequestReport) -> PlannedNotification {
        let pr = report.pullRequest
        return PlannedNotification(
            kind: .agentFinished(name: agent.name, state: agent.state), key: pr.key, headSHA: pr.headSHA,
            title: "\(pr.repository.name) #\(pr.number)", subtitle: "\(agent.name): \(agent.summary)",
            body: pr.title, url: agent.url ?? pr.url
        )
    }

    static func describe(_ report: PullRequestReport) -> (subtitle: String, body: String) {
        let names: (AgentReport.State) -> String = { state in
            ListFormatter.localizedString(byJoining: report.agents.filter { $0.state == state }.map(\.name))
        }
        switch report.status {
        case .failing:
            return ("Checks failed", "\(names(.failed)) failed.")
        case .needsReview:
            let threads = report.openThreadCount
            let who = names(.needsReview)
            if threads > 0 {
                let count = threads == 1 ? "1 open thread" : "\(threads) open threads"
                return ("Ready for your review", who.isEmpty ? "\(count)." : "\(count) from \(who).")
            }
            return ("Changes requested", who.isEmpty ? "A reviewer requested changes." : "\(who) requested changes.")
        case .ready:
            let count = report.agents.count
            return ("All clear", count == 1 ? "\(report.agents[0].name) passed with no feedback." : "All \(count) agents passed with no feedback.")
        case .running, .quiet:
            return ("Updated", "")
        }
    }
}
