import Foundation
import Testing
@testable import PRMonitor

/// Decodes synthetic payloads shaped exactly like GitHub's GraphQL responses (captured against the
/// live API, then anonymized) and checks the mapping into the domain model.
@Suite("GraphQL decoding")
struct GraphQLDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try GitHubClient.decoder.decode(T.self, from: Data(json.utf8))
    }

    @Test func listPayloadKeepsGoodRepositoriesWhenOneFails() throws {
        let payload = try decode(PullRequestQueries.ListPayload.self, """
        {
          "viewer": { "login": "hasaam" },
          "rateLimit": { "remaining": 4812, "resetAt": "2026-09-29T00:06:55Z" },
          "r0": {
            "pullRequests": {
              "totalCount": 1,
              "nodes": [{
                "id": "PR_1", "updatedAt": "2026-09-25T20:33:43Z", "headRefOid": "abc",
                "commits": { "nodes": [{ "commit": { "statusCheckRollup": { "state": "PENDING" } } }] }
              }]
            }
          },
          "r1": null
        }
        """)
        #expect(payload.viewerLogin == "hasaam")
        #expect(payload.rateLimit?.remaining == 4812)
        #expect(payload.repositories.count == 2)
        let item = try #require(payload.repositories["r0"] ?? nil).pullRequests.nodes.first
        #expect(item?.hasPendingChecks == true)
        #expect((payload.repositories["r1"] ?? nil) == nil)
    }

    @Test func graphQLErrorsMapBackToTheirAlias() throws {
        let error = try decode(GraphQLError.self, """
        { "type": "NOT_FOUND", "path": ["r2"], "message": "Could not resolve to a Repository with the name 'acme/gone'." }
        """)
        #expect(error.rootField == "r2")
        #expect(error.type == "NOT_FOUND")
    }

    @Test func detailPayloadMapsIntoAPullRequest() throws {
        let payload = try decode(PullRequestQueries.DetailPayload.self, Self.detailJSON)
        let pr = try #require(payload.nodes.first ?? nil).toPullRequest()

        #expect(pr.repository == RepositoryID(owner: "acme", name: "rocket"))
        #expect(pr.number == 857)
        #expect(pr.isDraft)
        #expect(pr.mergeable == .conflicting)
        #expect(pr.reviewDecision == .changesRequested)
        #expect(pr.rollupState == "FAILURE")

        // Check runs, a commit status, and a workflow awaiting approval.
        #expect(pr.checks.map(\.name) == ["Semgrep", "Deploy Preview", "Vercel", "Netlify"])
        #expect(pr.checks.map(\.outcome) == [.failed, .pending, .succeeded, .failed])
        #expect(pr.checks[3].rawState == "ACTION_REQUIRED")
        #expect(pr.checks[2].groupKey == "vercel")

        #expect(pr.requestedReviewers == [ReviewRequestSignal(login: "copilot-pull-request-reviewer", isBot: true)])
        #expect(pr.reviews.first?.commitSHA == "old999")
        #expect(pr.reviews.first?.isBot == true)
        #expect(pr.threads.count == 2, "The thread whose author was deleted is dropped")
        #expect(pr.threads.filter(\.isOpen).count == 1)
        #expect(pr.comments.map(\.author) == ["cursor"])
    }

    @Test func nullNodesAreSkippedRatherThanFailingTheBatch() throws {
        let payload = try decode(PullRequestQueries.DetailPayload.self, #"{ "nodes": [null] }"#)
        #expect(payload.nodes.count == 1)
        #expect(payload.nodes[0] == nil)
    }

    static let detailJSON = """
    {
      "nodes": [{
        "id": "PR_857", "number": 857, "title": "Market detail page", "url": "https://github.com/acme/rocket/pull/857",
        "isDraft": true, "createdAt": "2026-08-10T10:00:00Z", "updatedAt": "2026-08-17T19:45:41Z",
        "reviewDecision": "CHANGES_REQUESTED", "mergeable": "CONFLICTING", "headRefOid": "head123",
        "repository": { "name": "rocket", "owner": { "login": "acme" } },
        "author": { "__typename": "User", "login": "hasaam" },
        "commits": { "nodes": [{ "commit": {
          "committedDate": "2026-08-17T19:45:33Z",
          "checkSuites": { "nodes": [
            { "conclusion": "ACTION_REQUIRED", "app": { "name": "Netlify", "slug": "netlify" } },
            { "conclusion": "SUCCESS", "app": { "name": "GitHub Actions", "slug": "github-actions" } }
          ] },
          "statusCheckRollup": { "state": "FAILURE", "contexts": { "nodes": [
            { "__typename": "CheckRun", "name": "Semgrep", "status": "COMPLETED", "conclusion": "FAILURE",
              "startedAt": "2026-08-17T19:45:44Z", "completedAt": "2026-08-17T19:47:00Z",
              "detailsUrl": "https://github.com/acme/rocket/actions/runs/1", "checkSuite": { "app": { "name": "GitHub Actions", "slug": "github-actions" } } },
            { "__typename": "CheckRun", "name": "Deploy Preview", "status": "QUEUED", "conclusion": null,
              "startedAt": null, "completedAt": null, "detailsUrl": null, "checkSuite": { "app": { "name": "Supabase", "slug": "supabase" } } },
            { "__typename": "StatusContext", "context": "Vercel", "state": "SUCCESS", "createdAt": "2026-08-17T19:46:10Z",
              "targetUrl": "https://vercel.com/acme/rocket/1", "creator": { "login": "vercel" } }
          ] } }
        } }] },
        "reviewRequests": { "nodes": [
          { "requestedReviewer": { "__typename": "Bot", "login": "copilot-pull-request-reviewer" } },
          { "requestedReviewer": { "__typename": "Team" } }
        ] },
        "latestReviews": { "nodes": [
          { "author": { "__typename": "Bot", "login": "chatgpt-codex-connector" }, "state": "COMMENTED",
            "submittedAt": "2026-08-16T12:00:00Z", "commit": { "oid": "old999" } }
        ] },
        "reviewThreads": { "nodes": [
          { "isResolved": false, "isOutdated": false, "comments": { "nodes": [{ "author": { "__typename": "Bot", "login": "chatgpt-codex-connector" }, "createdAt": "2026-08-16T12:00:00Z" }] } },
          { "isResolved": false, "isOutdated": true, "comments": { "nodes": [{ "author": { "__typename": "Bot", "login": "chatgpt-codex-connector" }, "createdAt": "2026-08-15T12:00:00Z" }] } },
          { "isResolved": true, "isOutdated": false, "comments": { "nodes": [{ "author": null, "createdAt": "2026-08-14T12:00:00Z" }] } }
        ] },
        "comments": { "nodes": [ { "author": { "__typename": "Bot", "login": "cursor" }, "createdAt": "2026-08-17T19:50:00Z" } ] }
      }]
    }
    """
}

@Suite("Settings migration")
@MainActor
struct SettingsMigrationTests {
    private func defaults(with legacy: String) -> UserDefaults {
        let suite = "PRMonitorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(Data(legacy.utf8), forKey: "PRMonitorSettings")
        return defaults
    }

    @Test func untouchedSeededAgentsMigrateToAutomaticMode() {
        let settings = AppSettings(defaults: defaults(with: """
        { "repos": [{ "owner": "acme", "name": "rocket", "isEnabled": true }, { "owner": "acme", "name": "old", "isEnabled": false }],
          "agents": [
            { "id": "\(UUID())", "displayName": "Vercel", "checkNamePattern": "vercel", "commentAuthor": "vercel" },
            { "id": "\(UUID())", "displayName": "Cursor Bugbot", "checkNamePattern": "cursor", "commentAuthor": "cursor" },
            { "id": "\(UUID())", "displayName": "Devin Review", "checkNamePattern": "devin", "commentAuthor": "devin-ai-integration" }
          ],
          "pollingIntervalSeconds": 120, "notifyPerAgent": true, "notifySummary": false, "githubClientId": "Iv1.abc" }
        """))
        #expect(settings.enabledRepositories == [RepositoryID(owner: "acme", name: "rocket")])
        #expect(settings.repositories.count == 2)
        #expect(settings.agentMode == .automatic)
        #expect(settings.refreshInterval == 120)
        #expect(settings.notifiesPerAgent)
        #expect(!settings.notifiesWhenSettled)
        #expect(settings.oauthClientIDOverride == "Iv1.abc")
    }

    @Test func customizedAgentsAreKept() {
        let settings = AppSettings(defaults: defaults(with: """
        { "repos": [], "agents": [{ "id": "\(UUID())", "displayName": "CodeRabbit", "checkNamePattern": "coderabbit", "commentAuthor": "coderabbitai" }] }
        """))
        #expect(settings.agentMode == .custom)
        #expect(settings.agents.map(\.login) == ["coderabbitai"])
    }

    @Test func settingsRoundTripThroughStorage() {
        let defaults = UserDefaults(suiteName: "PRMonitorTests.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.track(RepositoryID(owner: "acme", name: "rocket"))
        settings.scope = .authored
        settings.agentMode = .custom

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.repositories.map(\.id.fullName) == ["acme/rocket"])
        #expect(reloaded.scope == .authored)
        #expect(reloaded.agentMode == .custom)
    }
}
