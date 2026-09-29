import Foundation
@testable import PRMonitor

/// Builders for hand-written pull request states. Every test reads as "given this PR…".
enum Fixture {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let repository = RepositoryID(owner: "acme", name: "rocket")

    static func pullRequest(
        number: Int = 1,
        headSHA: String = "aaa111",
        committedMinutesAgo: Double = 30,
        createdMinutesAgo: Double = 120,
        author: String = "hasaam",
        isDraft: Bool = false,
        rollupState: String? = nil,
        reviewDecision: ReviewDecision? = nil,
        checks: [CheckSignal] = [],
        requested: [ReviewRequestSignal] = [],
        reviews: [ReviewSignal] = [],
        threads: [ThreadSignal] = [],
        comments: [CommentSignal] = []
    ) -> PullRequest {
        PullRequest(
            id: "PR_\(number)",
            repository: repository,
            number: number,
            title: "Add launch sequence",
            url: URL(string: "https://github.com/acme/rocket/pull/\(number)")!,
            author: author,
            isDraft: isDraft,
            createdAt: now.addingTimeInterval(-createdMinutesAgo * 60),
            updatedAt: now.addingTimeInterval(-60),
            headSHA: headSHA,
            headCommittedAt: now.addingTimeInterval(-committedMinutesAgo * 60),
            rollupState: rollupState,
            reviewDecision: reviewDecision,
            mergeable: .mergeable,
            checks: checks,
            requestedReviewers: requested,
            reviews: reviews,
            threads: threads,
            comments: comments
        )
    }

    static func checkRun(_ name: String, app: String, slug: String, _ outcome: CheckSignal.Outcome, raw: String? = nil) -> CheckSignal {
        CheckSignal(
            name: name,
            source: .checkRun(appName: app, appSlug: slug),
            outcome: outcome,
            rawState: raw ?? defaultRaw(outcome),
            startedAt: now.addingTimeInterval(-600),
            completedAt: outcome == .pending ? nil : now.addingTimeInterval(-300),
            url: URL(string: "https://example.com/\(slug)/\(name)")
        )
    }

    static func status(_ context: String, creator: String, _ outcome: CheckSignal.Outcome) -> CheckSignal {
        CheckSignal(
            name: context,
            source: .commitStatus(creator: creator),
            outcome: outcome,
            rawState: outcome == .pending ? "PENDING" : outcome == .failed ? "FAILURE" : "SUCCESS",
            startedAt: now.addingTimeInterval(-500),
            completedAt: outcome == .pending ? nil : now.addingTimeInterval(-400),
            url: nil
        )
    }

    static func thread(by author: String, bot: Bool = true, resolved: Bool = false, outdated: Bool = false) -> ThreadSignal {
        ThreadSignal(author: author, isBot: bot, isResolved: resolved, isOutdated: outdated, createdAt: now.addingTimeInterval(-200))
    }

    static func review(by author: String, _ state: ReviewSignal.State, sha: String? = "aaa111", bot: Bool = true) -> ReviewSignal {
        ReviewSignal(author: author, isBot: bot, state: state, submittedAt: now.addingTimeInterval(-250), commitSHA: sha)
    }

    private static func defaultRaw(_ outcome: CheckSignal.Outcome) -> String {
        switch outcome {
        case .pending: "IN_PROGRESS"
        case .succeeded: "SUCCESS"
        case .neutral: "SKIPPED"
        case .failed: "FAILURE"
        }
    }
}

extension StatusEngine {
    static let automatic = StatusEngine(mode: .automatic, agents: [])

    func callAsFunction(_ pr: PullRequest) -> PullRequestReport {
        report(for: pr, now: Fixture.now)
    }
}
