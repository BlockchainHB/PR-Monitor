import Foundation
import Testing
@testable import PRMonitor

@Suite("Status engine")
struct StatusEngineTests {
    typealias F = Fixture

    // MARK: - Automatic mode

    @Test func groupsJobsFromTheSameIntegrationIntoOneAgent() {
        let report = StatusEngine.automatic(F.pullRequest(checks: [
            F.checkRun("build", app: "GitHub Actions", slug: "github-actions", .succeeded),
            F.checkRun("test", app: "GitHub Actions", slug: "github-actions", .succeeded),
            F.checkRun("lint", app: "GitHub Actions", slug: "github-actions", .succeeded),
        ]))
        #expect(report.agents.map(\.name) == ["GitHub Actions"])
        #expect(report.agents[0].summary == "3 checks passed")
        #expect(report.status == .ready)
    }

    @Test func mergesACommitStatusAndCheckRunFromTheSameBot() {
        // Vercel reports both a commit status and a "Preview Comments" check run.
        let report = StatusEngine.automatic(F.pullRequest(checks: [
            F.status("Vercel", creator: "vercel", .succeeded),
            F.checkRun("Vercel Preview Comments", app: "Vercel", slug: "vercel", .succeeded),
        ]))
        #expect(report.agents.count == 1)
        #expect(report.agents[0].name == "Vercel")
    }

    @Test func oneFailedJobFailsTheWholeAgentEvenWhileOthersRun() {
        let report = StatusEngine.automatic(F.pullRequest(checks: [
            F.checkRun("build", app: "GitHub Actions", slug: "github-actions", .failed),
            F.checkRun("test", app: "GitHub Actions", slug: "github-actions", .pending),
            F.checkRun("lint", app: "GitHub Actions", slug: "github-actions", .succeeded),
        ]))
        #expect(report.agents[0].state == .failed)
        #expect(report.agents[0].summary == "1 of 3 failed")
        #expect(report.status == .failing)
        #expect(report.isSettled, "A failed agent counts as finished: the failure is already actionable")
    }

    @Test func failureOutranksRunningAtThePullRequestLevel() {
        let report = StatusEngine.automatic(F.pullRequest(checks: [
            F.checkRun("build", app: "GitHub Actions", slug: "github-actions", .failed),
            F.checkRun("Bugbot", app: "Cursor", slug: "cursor", .pending),
        ]))
        #expect(report.status == .failing)
        #expect(!report.isSettled, "Cursor is still running, so the PR hasn't settled")
    }

    @Test func reviewOnlyBotsBecomeAgentsButCommentOnlyBotsDoNot() {
        let report = StatusEngine.automatic(F.pullRequest(
            threads: [F.thread(by: "chatgpt-codex-connector")],
            comments: [CommentSignal(author: "changeset-bot", isBot: true, createdAt: F.now)]
        ))
        #expect(report.agents.map(\.name) == ["Codex"])
        #expect(report.agents[0].state == .needsReview)
        #expect(report.agents[0].summary == "1 open thread")
    }

    @Test func humanThreadsDoNotCreateAgents() {
        let report = StatusEngine.automatic(F.pullRequest(threads: [F.thread(by: "octocat", bot: false)]))
        #expect(report.agents.isEmpty)
        #expect(report.status == .quiet)
        #expect(report.openThreadCount == 1)
    }

    @Test func resolvedAndOutdatedThreadsDoNotNeedReview() {
        let report = StatusEngine.automatic(F.pullRequest(
            checks: [F.checkRun("Bugbot", app: "Cursor", slug: "cursor", .succeeded)],
            reviews: [F.review(by: "cursor", .commented)],
            threads: [F.thread(by: "cursor", resolved: true), F.thread(by: "cursor", outdated: true)]
        ))
        #expect(report.agents.map(\.state) == [.passed])
        #expect(report.status == .ready)
    }

    @Test func aPendingReviewRequestMeansTheBotIsStillReviewing() {
        let report = StatusEngine.automatic(F.pullRequest(
            requested: [ReviewRequestSignal(login: "copilot-pull-request-reviewer", isBot: true)]
        ))
        #expect(report.agents.map(\.name) == ["Copilot"])
        #expect(report.agents[0].state == .running)
        #expect(report.agents[0].summary == "Reviewing")
    }

    @Test func skippedAndCancelledChecksAreNotFailures() {
        let report = StatusEngine.automatic(F.pullRequest(checks: [
            F.checkRun("Supabase Preview", app: "Supabase", slug: "supabase", .neutral, raw: "SKIPPED"),
            F.checkRun("deploy", app: "Netlify", slug: "netlify", .neutral, raw: "CANCELLED"),
        ]))
        #expect(report.agents.map(\.summary) == ["Skipped", "Cancelled"])
        #expect(report.status == .ready)
    }

    @Test func trustsAPendingRollupWhenNoVisibleCheckIsPending() {
        let report = StatusEngine.automatic(F.pullRequest(
            rollupState: "PENDING",
            checks: [F.checkRun("build", app: "GitHub Actions", slug: "github-actions", .succeeded)]
        ))
        #expect(report.status == .running)
        #expect(report.agents.contains { $0.id == "rollup" })
    }

    @Test func aHumanRequestingChangesKeepsThePullRequestInReview() {
        let report = StatusEngine.automatic(F.pullRequest(
            reviewDecision: .changesRequested,
            checks: [F.checkRun("build", app: "GitHub Actions", slug: "github-actions", .succeeded)]
        ))
        #expect(report.status == .needsReview)
    }

    // MARK: - Stale reviews

    @Test func aReviewOfAnOlderCommitIsAssumedToBeRedoneShortlyAfterAPush() {
        let pr = F.pullRequest(headSHA: "new222", committedMinutesAgo: 1, reviews: [F.review(by: "chatgpt-codex-connector", .commented, sha: "old111")])
        let report = StatusEngine.automatic(pr)
        #expect(report.agents[0].state == .running)
        #expect(report.agents[0].summary == "Waiting to review")
    }

    @Test func aReviewOfAnOlderCommitSettlesAfterTheGracePeriod() {
        let pr = F.pullRequest(headSHA: "new222", committedMinutesAgo: 20, reviews: [F.review(by: "chatgpt-codex-connector", .commented, sha: "old111")])
        let report = StatusEngine.automatic(pr)
        #expect(report.agents[0].state == .passed)
        #expect(report.agents[0].summary == "Reviewed an earlier commit")
    }

    // MARK: - Custom mode

    @Test func customAgentsMatchChecksByPatternAndReviewsByLogin() {
        let engine = StatusEngine(mode: .custom, agents: [
            Agent(name: "Bugbot", checkPattern: "cursor", login: "cursor"),
        ])
        let report = engine(F.pullRequest(
            checks: [
                F.checkRun("Cursor Bugbot", app: "Cursor", slug: "cursor", .succeeded),
                F.checkRun("build", app: "GitHub Actions", slug: "github-actions", .failed),
            ],
            threads: [F.thread(by: "cursor[bot]"), F.thread(by: "cursor"), F.thread(by: "someone-else")]
        ))
        #expect(report.agents.map(\.name) == ["Bugbot"])
        #expect(report.agents[0].openThreads == 2, "REST-style `cursor[bot]` and GraphQL-style `cursor` are the same bot")
        #expect(report.status == .needsReview, "The failing Actions job isn't a configured agent, so it's ignored")
    }

    @Test func aConfiguredAgentThatHasNotReportedIsExpectedRightAfterAPush() {
        let engine = StatusEngine(mode: .custom, agents: [Agent(name: "Devin", login: "devin-ai-integration")])
        let justPushed = engine(F.pullRequest(committedMinutesAgo: 1))
        #expect(justPushed.agents.map(\.summary) == ["Waiting to start"])
        #expect(justPushed.status == .running)

        let later = engine(F.pullRequest(committedMinutesAgo: 30))
        #expect(later.agents.isEmpty, "After the grace period it's treated as not applicable")
        #expect(later.status == .quiet)
    }

    @Test func invalidAgentsAreIgnored() {
        let engine = StatusEngine(mode: .custom, agents: [Agent(name: "Nothing")])
        #expect(engine(F.pullRequest(checks: [F.checkRun("x", app: "X", slug: "x", .failed)])).agents.isEmpty)
    }
}
