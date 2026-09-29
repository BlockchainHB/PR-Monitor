import Foundation

/// GraphQL documents and response types for monitoring pull requests.
///
/// Fetching happens in two phases to stay far below GitHub's 5,000 points/hour budget:
/// 1. A **list** query batches many repositories into one request using aliases (`r0`, `r1`…) and
///    returns just enough to fingerprint each open PR (~1 point per repository).
/// 2. A **detail** query loads checks, reviews and threads by node ID, but only for PRs whose
///    fingerprint changed or that still have work in flight.
enum PullRequestQueries {
    static let pullRequestsPerRepository = 50

    // MARK: - List

    static func listDocument(repositoryCount: Int) -> String {
        let parameters = (0..<repositoryCount).map { "$o\($0): String!, $n\($0): String!" }.joined(separator: ", ")
        let fields = (0..<repositoryCount).map { "r\($0): repository(owner: $o\($0), name: $n\($0)) { ...ListFields }" }
            .joined(separator: "\n  ")
        return """
        query PRMonitorList(\(parameters)) {
          viewer { login }
          rateLimit { remaining resetAt }
          \(fields)
        }
        fragment ListFields on Repository {
          pullRequests(states: OPEN, first: \(pullRequestsPerRepository), orderBy: {field: UPDATED_AT, direction: DESC}) {
            totalCount
            nodes {
              id
              updatedAt
              headRefOid
              commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
            }
          }
        }
        """
    }

    static func listVariables(for repositories: [RepositoryID]) -> [String: GraphQLVariable] {
        var variables: [String: GraphQLVariable] = [:]
        for (index, repository) in repositories.enumerated() {
            variables["o\(index)"] = .string(repository.owner)
            variables["n\(index)"] = .string(repository.name)
        }
        return variables
    }

    struct ListPayload: Decodable, Sendable {
        let viewerLogin: String?
        let rateLimit: RateLimitDTO?
        /// Keyed by alias. A `nil` value means GitHub couldn't resolve that repository.
        let repositories: [String: RepositoryListDTO?]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicKey.self)
            viewerLogin = try container.decodeIfPresent(ViewerDTO.self, forKey: DynamicKey("viewer"))?.login
            rateLimit = try container.decodeIfPresent(RateLimitDTO.self, forKey: DynamicKey("rateLimit"))
            var repositories: [String: RepositoryListDTO?] = [:]
            for key in container.allKeys where key.stringValue.wholeMatch(of: /r\d+/) != nil {
                repositories[key.stringValue] = try container.decodeIfPresent(RepositoryListDTO.self, forKey: key)
            }
            self.repositories = repositories
        }
    }

    struct RepositoryListDTO: Decodable, Sendable {
        let pullRequests: Connection<ListItemDTO>
    }

    struct ListItemDTO: Decodable, Sendable {
        let id: String
        let updatedAt: Date
        let headRefOid: String
        let commits: Nodes<CommitWrapper<RollupStateCommit>>

        var rollupState: String? { commits.nodes.last?.commit.statusCheckRollup?.state }
        /// Changes whenever the PR is pushed, commented on, reviewed, or its checks move.
        var fingerprint: String { "\(updatedAt.timeIntervalSince1970)|\(headRefOid)|\(rollupState ?? "-")" }
        /// A pending rollup means some check is still running, and per-check progress can change
        /// without the fingerprint changing.
        var hasPendingChecks: Bool { rollupState == "PENDING" || rollupState == "EXPECTED" }
    }

    struct RollupStateCommit: Decodable, Sendable {
        struct Rollup: Decodable, Sendable { let state: String }
        let statusCheckRollup: Rollup?
    }

    // MARK: - Detail

    static let detailBatchSize = 20

    static let detailDocument = """
    query PRMonitorDetails($ids: [ID!]!) {
      nodes(ids: $ids) {
        ... on PullRequest {
          id number title url isDraft createdAt updatedAt reviewDecision mergeable headRefOid
          repository { name owner { login } }
          author { __typename login }
          commits(last: 1) {
            nodes {
              commit {
                committedDate
                checkSuites(last: 20) { nodes { conclusion app { name slug } } }
                statusCheckRollup {
                  state
                  contexts(first: 100) {
                    nodes {
                      __typename
                      ... on CheckRun {
                        name status conclusion startedAt completedAt detailsUrl
                        checkSuite { app { name slug } }
                      }
                      ... on StatusContext { context state createdAt targetUrl creator { login } }
                    }
                  }
                }
              }
            }
          }
          reviewRequests(first: 20) {
            nodes { requestedReviewer { __typename ... on User { login } ... on Bot { login } ... on Mannequin { login } } }
          }
          latestReviews(first: 30) { nodes { author { __typename login } state submittedAt commit { oid } } }
          reviewThreads(first: 100) {
            nodes { isResolved isOutdated comments(first: 1) { nodes { author { __typename login } createdAt } } }
          }
          comments(last: 30) { nodes { author { __typename login } createdAt } }
        }
      }
    }
    """

    struct DetailPayload: Decodable, Sendable {
        /// `nil` entries are PRs that were closed or became inaccessible between the two phases.
        let nodes: [PullRequestDTO?]
    }

    struct PullRequestDTO: Decodable, Sendable {
        struct Repository: Decodable, Sendable {
            let name: String
            let owner: ActorDTO
        }

        struct DetailCommit: Decodable, Sendable {
            struct Rollup: Decodable, Sendable {
                let state: String?
                let contexts: Nodes<ContextDTO>
            }
            struct Suite: Decodable, Sendable {
                struct App: Decodable, Sendable { let name: String?; let slug: String? }
                let conclusion: String?
                let app: App?
            }
            let committedDate: Date?
            let checkSuites: Nodes<Suite>?
            let statusCheckRollup: Rollup?
        }

        struct ReviewRequest: Decodable, Sendable { let requestedReviewer: ActorDTO? }
        struct Review: Decodable, Sendable {
            struct Commit: Decodable, Sendable { let oid: String }
            let author: ActorDTO?
            let state: String
            let submittedAt: Date?
            let commit: Commit?
        }
        struct Thread: Decodable, Sendable {
            let isResolved: Bool
            let isOutdated: Bool
            let comments: Nodes<Comment>
        }
        struct Comment: Decodable, Sendable {
            let author: ActorDTO?
            let createdAt: Date
        }

        let id: String
        let number: Int
        let title: String
        let url: URL
        let isDraft: Bool
        let createdAt: Date
        let updatedAt: Date
        let reviewDecision: String?
        let mergeable: String
        let headRefOid: String
        let repository: Repository
        let author: ActorDTO?
        let commits: Nodes<CommitWrapper<DetailCommit>>
        let reviewRequests: Nodes<ReviewRequest>
        let latestReviews: Nodes<Review>
        let reviewThreads: Nodes<Thread>
        let comments: Nodes<Comment>
    }

    enum ContextDTO: Decodable, Sendable {
        case checkRun(name: String, status: String, conclusion: String?, startedAt: Date?, completedAt: Date?,
                      detailsUrl: URL?, appName: String?, appSlug: String?)
        case status(context: String, state: String, createdAt: Date?, targetUrl: URL?, creator: String?)
        case unknown

        private enum CodingKeys: String, CodingKey {
            case __typename, name, status, conclusion, startedAt, completedAt, detailsUrl, checkSuite
            case context, state, createdAt, targetUrl, creator
        }

        private struct CheckSuite: Decodable {
            struct App: Decodable { let name: String?; let slug: String? }
            let app: App?
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(String.self, forKey: .__typename) {
            case "CheckRun":
                let app = try c.decodeIfPresent(CheckSuite.self, forKey: .checkSuite)?.app
                self = .checkRun(
                    name: try c.decode(String.self, forKey: .name),
                    status: try c.decode(String.self, forKey: .status),
                    conclusion: try c.decodeIfPresent(String.self, forKey: .conclusion),
                    startedAt: try c.decodeIfPresent(Date.self, forKey: .startedAt),
                    completedAt: try c.decodeIfPresent(Date.self, forKey: .completedAt),
                    detailsUrl: try? c.decodeIfPresent(URL.self, forKey: .detailsUrl),
                    appName: app?.name,
                    appSlug: app?.slug
                )
            case "StatusContext":
                self = .status(
                    context: try c.decode(String.self, forKey: .context),
                    state: try c.decode(String.self, forKey: .state),
                    createdAt: try c.decodeIfPresent(Date.self, forKey: .createdAt),
                    targetUrl: try? c.decodeIfPresent(URL.self, forKey: .targetUrl),
                    creator: try c.decodeIfPresent(ActorDTO.self, forKey: .creator)?.login
                )
            default:
                self = .unknown
            }
        }
    }

    // MARK: - Shared shapes

    struct ViewerDTO: Decodable, Sendable { let login: String }

    struct RateLimitDTO: Decodable, Sendable {
        let remaining: Int
        let resetAt: Date
    }

    struct ActorDTO: Decodable, Sendable {
        let __typename: String?
        let login: String?
        var isBot: Bool { __typename == "Bot" }
    }

    struct Connection<Node: Decodable & Sendable>: Decodable, Sendable {
        let totalCount: Int
        let nodes: [Node]
    }

    struct Nodes<Node: Decodable & Sendable>: Decodable, Sendable {
        let nodes: [Node]

        init(from decoder: Decoder) throws {
            // GitHub returns `null` for entries it can't resolve; drop them rather than fail the page.
            let container = try decoder.container(keyedBy: DynamicKey.self)
            nodes = try container.decodeIfPresent([Lossy<Node>].self, forKey: DynamicKey("nodes"))?.compactMap(\.value) ?? []
        }
    }

    struct Lossy<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
    }

    struct CommitWrapper<Commit: Decodable & Sendable>: Decodable, Sendable { let commit: Commit }

    struct DynamicKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

// MARK: - Mapping into the domain

extension PullRequestQueries.PullRequestDTO {
    func toPullRequest() -> PullRequest {
        let commit = commits.nodes.last?.commit
        var checks: [CheckSignal] = (commit?.statusCheckRollup?.contexts.nodes ?? []).compactMap { $0.toSignal() }
        // Workflows awaiting approval (e.g. from a first-time contributor's fork) have a check suite
        // but no check runs, so they're invisible in the roll-up contexts. Surface them explicitly.
        for suite in commit?.checkSuites?.nodes ?? [] where suite.conclusion == "ACTION_REQUIRED" {
            let signal = CheckSignal(
                name: suite.app?.name ?? "Workflow", source: .checkRun(appName: suite.app?.name, appSlug: suite.app?.slug),
                outcome: .failed, rawState: "ACTION_REQUIRED", startedAt: nil, completedAt: nil, url: url.appending(path: "checks")
            )
            if !checks.contains(where: { $0.groupKey == signal.groupKey }) { checks.append(signal) }
        }

        return PullRequest(
            id: id,
            repository: RepositoryID(owner: repository.owner.login ?? "", name: repository.name),
            number: number,
            title: title,
            url: url,
            author: author?.login,
            isDraft: isDraft,
            createdAt: createdAt,
            updatedAt: updatedAt,
            headSHA: headRefOid,
            headCommittedAt: commit?.committedDate,
            rollupState: commit?.statusCheckRollup?.state,
            reviewDecision: reviewDecision.flatMap(ReviewDecision.init(rawValue:)),
            mergeable: Mergeable(rawValue: mergeable) ?? .unknown,
            checks: checks,
            requestedReviewers: reviewRequests.nodes.compactMap { request in
                guard let reviewer = request.requestedReviewer, let login = reviewer.login else { return nil }
                return ReviewRequestSignal(login: login, isBot: reviewer.isBot)
            },
            reviews: latestReviews.nodes.compactMap { review in
                guard let login = review.author?.login, let state = ReviewSignal.State(rawValue: review.state) else { return nil }
                return ReviewSignal(author: login, isBot: review.author?.isBot ?? false, state: state,
                                    submittedAt: review.submittedAt, commitSHA: review.commit?.oid)
            },
            threads: reviewThreads.nodes.compactMap { thread in
                guard let first = thread.comments.nodes.first, let login = first.author?.login else { return nil }
                return ThreadSignal(author: login, isBot: first.author?.isBot ?? false, isResolved: thread.isResolved,
                                    isOutdated: thread.isOutdated, createdAt: first.createdAt)
            },
            comments: comments.nodes.compactMap { comment in
                guard let login = comment.author?.login else { return nil }
                return CommentSignal(author: login, isBot: comment.author?.isBot ?? false, createdAt: comment.createdAt)
            }
        )
    }
}

extension PullRequestQueries.ContextDTO {
    func toSignal() -> CheckSignal? {
        switch self {
        case let .checkRun(name, status, conclusion, startedAt, completedAt, detailsUrl, appName, appSlug):
            let outcome: CheckSignal.Outcome = if status != "COMPLETED" {
                .pending
            } else {
                switch conclusion {
                case "SUCCESS": .succeeded
                case "NEUTRAL", "SKIPPED", "CANCELLED", "STALE": .neutral
                case nil: .pending
                default: .failed // FAILURE, TIMED_OUT, ACTION_REQUIRED, STARTUP_FAILURE
                }
            }
            return CheckSignal(name: name, source: .checkRun(appName: appName, appSlug: appSlug), outcome: outcome,
                               rawState: conclusion ?? status, startedAt: startedAt, completedAt: completedAt, url: detailsUrl)
        case let .status(context, state, createdAt, targetUrl, creator):
            let outcome: CheckSignal.Outcome = switch state {
            case "SUCCESS": .succeeded
            case "PENDING", "EXPECTED": .pending
            default: .failed // FAILURE, ERROR
            }
            // Statuses have no start/finish; `createdAt` is when this state was reported.
            return CheckSignal(name: context, source: .commitStatus(creator: creator), outcome: outcome, rawState: state,
                               startedAt: createdAt, completedAt: outcome == .pending ? nil : createdAt, url: targetUrl)
        case .unknown:
            return nil
        }
    }
}
