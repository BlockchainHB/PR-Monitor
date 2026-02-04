import Foundation

final class PollingService {
    let client: GitHubClient

    init(client: GitHubClient) {
        self.client = client
    }

    func fetchRepoSections(repos: [RepoConfig], agents: [AgentConfig]) async throws -> [RepoSection] {
        guard !repos.isEmpty else { return [] }

        return try await withThrowingTaskGroup(of: RepoSection?.self) { group in
            for repo in repos {
                group.addTask {
                    let pulls = try await self.client.fetchOpenPullRequests(repo: repo)
                    let prs = try await self.buildPRItems(repo: repo, pulls: pulls, agents: agents)
                    return RepoSection(fullName: repo.fullName, prs: prs)
                }
            }

            var sections: [RepoSection] = []
            for try await section in group {
                if let section = section {
                    sections.append(section)
                }
            }
            return sections.sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
        }
    }

    private func buildPRItems(repo: RepoConfig, pulls: [PullRequestDTO], agents: [AgentConfig]) async throws -> [PRItem] {
        return try await withThrowingTaskGroup(of: PRItem?.self) { group in
            for pr in pulls {
                group.addTask {
                    async let checkRuns = self.client.fetchCheckRuns(owner: repo.owner, repo: repo.name, sha: pr.head.sha)
                    async let comments = self.client.fetchReviewComments(owner: repo.owner, repo: repo.name, prNumber: pr.number)
                    let resolvedCheckRuns = try await checkRuns
                    let resolvedComments = try await comments
                    let agentRuns = self.buildAgentRuns(checkRuns: resolvedCheckRuns, comments: resolvedComments, agents: agents)
                    return PRItem(
                        id: pr.number,
                        number: pr.number,
                        title: pr.title,
                        author: pr.user.login,
                        updatedAt: pr.updatedAt,
                        url: URL(string: pr.htmlURL) ?? URL(string: "https://github.com")!,
                        repoFullName: repo.fullName,
                        agents: agentRuns
                    )
                }
            }

            var items: [PRItem] = []
            for try await item in group {
                if let item = item {
                    items.append(item)
                }
            }
            return items.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    private func buildAgentRuns(checkRuns: [CheckRunDTO], comments: [ReviewCommentDTO], agents: [AgentConfig]) -> [AgentRun] {
        if agents.isEmpty {
            return inferAgentRuns(checkRuns: checkRuns, comments: comments)
        }

        return agents.map { agent in
            let matchingRuns = checkRuns.filter { matches(checkRun: $0, agent: agent) }
            let bestRun = matchingRuns.sorted { lhs, rhs in
                (lhs.completedAt ?? .distantPast) > (rhs.completedAt ?? .distantPast)
            }.first

            let commentCount = commentCountForAgent(agent: agent, comments: comments)

            guard let run = bestRun else {
                return AgentRun(id: agent.id.uuidString, displayName: agent.displayName, status: .notFound, commentCount: commentCount, checkConclusion: nil)
            }

            let status = agentStatus(run: run, commentCount: commentCount)
            return AgentRun(id: agent.id.uuidString, displayName: agent.displayName, status: status, commentCount: commentCount, checkConclusion: run.conclusion)
        }
    }

    private func inferAgentRuns(checkRuns: [CheckRunDTO], comments: [ReviewCommentDTO]) -> [AgentRun] {
        var seen: Set<String> = []
        var runs: [AgentRun] = []

        for run in checkRuns {
            let display = run.app?.name ?? run.name
            guard !seen.contains(display) else { continue }
            seen.insert(display)

            let commentCount = inferCommentCount(app: run.app, comments: comments)
            let status = agentStatus(run: run, commentCount: commentCount)
            runs.append(AgentRun(id: display, displayName: display, status: status, commentCount: commentCount, checkConclusion: run.conclusion))
        }

        return runs.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func matches(checkRun: CheckRunDTO, agent: AgentConfig) -> Bool {
        let pattern = agent.checkNamePattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !pattern.isEmpty {
            if checkRun.name.lowercased().contains(pattern) {
                return true
            }
            if let appSlug = checkRun.app?.slug?.lowercased(), appSlug.contains(pattern) {
                return true
            }
            if let appName = checkRun.app?.name?.lowercased(), appName.contains(pattern) {
                return true
            }
        }

        let commentAuthor = agent.commentAuthor.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !commentAuthor.isEmpty, let appSlug = checkRun.app?.slug?.lowercased() {
            if commentAuthor.hasPrefix(appSlug) {
                return true
            }
        }

        return false
    }

    private func agentStatus(run: CheckRunDTO, commentCount: Int) -> AgentRunStatus {
        if run.status != "completed" {
            return .running
        }
        return commentCount > 0 ? .done : .waitingForComment
    }

    private func commentCountForAgent(agent: AgentConfig, comments: [ReviewCommentDTO]) -> Int {
        let author = agent.commentAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
        if !author.isEmpty {
            let normalizedAuthor = normalize(author)
            return comments.filter { normalize($0.user.login) == normalizedAuthor }.count
        }

        let normalized = normalize(agent.displayName)
        if normalized.isEmpty {
            return 0
        }
        return comments.filter { normalize($0.user.login) == normalized }.count
    }

    private func inferCommentCount(app: CheckRunDTO.App?, comments: [ReviewCommentDTO]) -> Int {
        guard let slug = app?.slug?.lowercased() else { return 0 }
        return comments.filter { normalize($0.user.login).hasPrefix(slug) }.count
    }

    private func normalize(_ value: String) -> String {
        let lowered = value.lowercased()
        let removedBot = lowered.replacingOccurrences(of: "[bot]", with: "")
        let allowed = removedBot.filter { $0.isLetter || $0.isNumber }
        return allowed
    }
}
