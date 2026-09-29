import Foundation
import Testing
@testable import PRMonitor

@Suite("Notification planner")
struct NotificationPlannerTests {
    typealias F = Fixture
    let engine = StatusEngine.automatic
    let preferences = NotificationPreferences()

    private func running(sha: String = "aaa111", number: Int = 1) -> PullRequestReport {
        engine(F.pullRequest(number: number, headSHA: sha, checks: [F.checkRun("build", app: "GitHub Actions", slug: "github-actions", .pending)]))
    }

    private func passed(sha: String = "aaa111", number: Int = 1, createdMinutesAgo: Double = 120) -> PullRequestReport {
        engine(F.pullRequest(number: number, headSHA: sha, createdMinutesAgo: createdMinutesAgo,
                             checks: [F.checkRun("build", app: "GitHub Actions", slug: "github-actions", .succeeded)]))
    }

    private func withFeedback(sha: String = "aaa111") -> PullRequestReport {
        engine(F.pullRequest(headSHA: sha, checks: [F.checkRun("build", app: "GitHub Actions", slug: "github-actions", .succeeded)],
                             threads: [F.thread(by: "cursor")]))
    }

    @Test func theFirstPollOnlyRecordsABaseline() {
        var planner = NotificationPlanner()
        #expect(planner.plan(for: [passed()], preferences: preferences, now: F.now).isEmpty)
    }

    @Test func announcesOnceWhenAPullRequestSettles() {
        var planner = NotificationPlanner()
        _ = planner.plan(for: [running()], preferences: preferences, now: F.now)

        let settled = planner.plan(for: [passed()], preferences: preferences, now: F.now)
        #expect(settled.count == 1)
        #expect(settled.first?.kind == .settled(.ready))
        #expect(settled.first?.subtitle == "All clear")

        #expect(planner.plan(for: [passed()], preferences: preferences, now: F.now).isEmpty, "No repeat on the next poll")
    }

    @Test func aNewPushStartsAFreshLifecycle() {
        var planner = NotificationPlanner()
        _ = planner.plan(for: [running()], preferences: preferences, now: F.now)
        _ = planner.plan(for: [passed()], preferences: preferences, now: F.now)

        // Pushed and finished between two polls: still announced, because it's a new commit.
        let next = planner.plan(for: [passed(sha: "bbb222")], preferences: preferences, now: F.now)
        #expect(next.count == 1)
        #expect(next.first?.headSHA == "bbb222")
    }

    @Test func feedbackAfterSettlingIsAnnouncedAsARegression() {
        var planner = NotificationPlanner()
        _ = planner.plan(for: [running()], preferences: preferences, now: F.now)
        _ = planner.plan(for: [passed()], preferences: preferences, now: F.now)

        let regressed = planner.plan(for: [withFeedback()], preferences: preferences, now: F.now)
        #expect(regressed.map(\.kind) == [.regressed(.needsReview)])
        #expect(regressed.first?.body.contains("1 open thread") == true)
    }

    @Test func pullRequestsThatExistedBeforeLaunchAreNotAnnouncedWhenTheyAppear() {
        var planner = NotificationPlanner()
        _ = planner.plan(for: [], preferences: preferences, now: F.now)
        // e.g. the user just enabled a repository with an old, already-green PR.
        #expect(planner.plan(for: [passed(number: 7)], preferences: preferences, now: F.now).isEmpty)
    }

    @Test func pullRequestsOpenedAfterLaunchAreAnnounced() {
        var planner = NotificationPlanner()
        let launch = F.now.addingTimeInterval(-3600)
        _ = planner.plan(for: [], preferences: preferences, now: launch)
        let planned = planner.plan(for: [passed(number: 8, createdMinutesAgo: 5)], preferences: preferences, now: F.now)
        #expect(planned.count == 1)
    }

    @Test func respectsPreferences() {
        var planner = NotificationPlanner()
        let off = NotificationPreferences(whenSettled: false, whenFeedbackArrives: false, perAgent: false)
        _ = planner.plan(for: [running()], preferences: off, now: F.now)
        #expect(planner.plan(for: [passed()], preferences: off, now: F.now).isEmpty)
    }

    @Test func perAgentNotificationsFireAsEachAgentFinishes() {
        var planner = NotificationPlanner()
        let perAgent = NotificationPreferences(whenSettled: false, whenFeedbackArrives: false, perAgent: true)
        let twoRunning = engine(F.pullRequest(checks: [
            F.checkRun("build", app: "GitHub Actions", slug: "github-actions", .pending),
            F.checkRun("Bugbot", app: "Cursor", slug: "cursor", .pending),
        ]))
        let oneDone = engine(F.pullRequest(checks: [
            F.checkRun("build", app: "GitHub Actions", slug: "github-actions", .succeeded),
            F.checkRun("Bugbot", app: "Cursor", slug: "cursor", .pending),
        ]))
        _ = planner.plan(for: [twoRunning], preferences: perAgent, now: F.now)
        let planned = planner.plan(for: [oneDone], preferences: perAgent, now: F.now)
        #expect(planned.map(\.kind) == [.agentFinished(name: "GitHub Actions", state: .passed)])
        #expect(planner.plan(for: [oneDone], preferences: perAgent, now: F.now).isEmpty)
    }

    @Test func identifiersAreStableSoRepeatsReplaceRatherThanStack() {
        var a = NotificationPlanner(), b = NotificationPlanner()
        _ = a.plan(for: [running()], preferences: preferences, now: F.now)
        _ = b.plan(for: [running()], preferences: preferences, now: F.now)
        let first = a.plan(for: [passed()], preferences: preferences, now: F.now)
        let second = b.plan(for: [passed()], preferences: preferences, now: F.now)
        #expect(first.map(\.identifier) == second.map(\.identifier))
        #expect(first.first?.identifier == "acme/rocket#1@aaa111/settled-ready")
    }
}

@Suite("Polling policy")
struct PollingPolicyTests {
    let policy = PollingPolicy(activeInterval: 60)

    @Test func pollsAtTheUsersIntervalWhileAgentsRun() {
        #expect(policy.delay(after: .success(hasRunningPullRequests: true, hasOpenPullRequests: true)) == 60)
    }

    @Test func slowsDownOnceEverythingSettles() {
        #expect(policy.delay(after: .success(hasRunningPullRequests: false, hasOpenPullRequests: true)) == 120)
        #expect(policy.delay(after: .success(hasRunningPullRequests: false, hasOpenPullRequests: false)) == 300)
    }

    @Test func backsOffExponentiallyOnFailure() {
        let delays = (1...6).map { policy.delay(after: .failure(consecutive: $0)) }
        #expect(delays == [30, 60, 120, 240, 480, 600])
    }

    @Test func waitsOutARateLimit() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(policy.delay(after: .rateLimited(resetAt: now.addingTimeInterval(900)), now: now) == 905)
        #expect(policy.delay(after: .rateLimited(resetAt: now.addingTimeInterval(-10)), now: now) == 30, "Never returns a negative or tiny wait")
    }
}
