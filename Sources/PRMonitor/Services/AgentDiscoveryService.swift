import Foundation

final class AgentDiscoveryService {
    private let client: GitHubClient

    init(client: GitHubClient) {
        self.client = client
    }

    func discoverAgents(repos: [RepoConfig]) async throws -> [AgentConfig] {
        var candidates: [String: AgentCandidate] = [:]

        for repo in repos {
            let pulls = try await client.fetchOpenPullRequests(repo: repo)
            for pr in pulls {
                async let checkRunsTask = client.fetchCheckRuns(owner: repo.owner, repo: repo.name, sha: pr.head.sha)
                async let commentsTask = client.fetchReviewComments(owner: repo.owner, repo: repo.name, prNumber: pr.number)
                let checkRuns = try await checkRunsTask
                let comments = try await commentsTask

                var localKeys: [String] = []

                for run in checkRuns {
                    let displayName = run.app?.name ?? run.name
                    let pattern = run.app?.slug ?? run.name
                    let key = normalize(pattern)
                    guard !key.isEmpty else { continue }
                    localKeys.append(key)
                    if candidates[key] == nil {
                        candidates[key] = AgentCandidate(displayName: displayName, checkPattern: pattern, commentCounts: [:])
                    }
                }

                for comment in comments {
                    let commentKey = normalize(comment.user.login)
                    guard !commentKey.isEmpty else { continue }
                    for key in localKeys {
                        if matches(candidateKey: key, commentKey: commentKey) {
                            candidates[key, default: AgentCandidate(displayName: key, checkPattern: key, commentCounts: [:])]
                                .commentCounts[comment.user.login, default: 0] += 1
                        }
                    }
                }
            }
        }

        return candidates.values
            .map { candidate in
                let bestAuthor = candidate.commentCounts.max(by: { $0.value < $1.value })?.key ?? ""
                return AgentConfig(
                    displayName: candidate.displayName,
                    checkNamePattern: candidate.checkPattern,
                    commentAuthor: bestAuthor
                )
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func normalize(_ value: String) -> String {
        let lowered = value.lowercased()
        let removedBot = lowered.replacingOccurrences(of: "[bot]", with: "")
        let allowed = removedBot.filter { $0.isLetter || $0.isNumber }
        return allowed
    }

    private func matches(candidateKey: String, commentKey: String) -> Bool {
        if candidateKey == commentKey { return true }
        if commentKey.contains(candidateKey) { return true }
        if candidateKey.contains(commentKey) { return true }
        return false
    }
}

private struct AgentCandidate {
    var displayName: String
    var checkPattern: String
    var commentCounts: [String: Int]
}
