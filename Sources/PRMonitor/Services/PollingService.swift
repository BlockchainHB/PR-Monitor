import Foundation

final class PollingService {
    let client: GitHubClient
    private let repoConcurrencyLimit = 4
    private let prConcurrencyLimit = 6

    init(client: GitHubClient) {
        self.client = client
    }

    func fetchRepoSections(repos: [RepoConfig], agents: [AgentConfig]) async throws -> [RepoSection] {
        guard !repos.isEmpty else { return [] }

        let repoSemaphore = AsyncSemaphore(value: repoConcurrencyLimit)
        return try await withThrowingTaskGroup(of: RepoSection?.self) { group in
            for repo in repos {
                group.addTask {
                    await repoSemaphore.wait()
                    defer { repoSemaphore.signal() }
                    print("   🔄 Fetching PRs for \(repo.fullName)...")
                    let pulls = try await self.client.fetchOpenPullRequests(repo: repo)
                    print("   📝 Found \(pulls.count) open PRs in \(repo.fullName)")
                    let prs = try await self.buildPRItems(repo: repo, pulls: pulls, agents: agents)
                    print("   ✅ Built \(prs.count) PR items for \(repo.fullName)")
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
        let prSemaphore = AsyncSemaphore(value: prConcurrencyLimit)
        return try await withThrowingTaskGroup(of: PRItem?.self) { group in
            for pr in pulls {
                group.addTask {
                    await prSemaphore.wait()
                    defer { prSemaphore.signal() }
                    async let checkRuns = self.client.fetchCheckRuns(owner: repo.owner, repo: repo.name, sha: pr.head.sha)
                    async let comments = self.client.fetchAllPRComments(owner: repo.owner, repo: repo.name, prNumber: pr.number)
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

    private func buildAgentRuns(checkRuns: [CheckRunDTO], comments: [PRComment], agents: [AgentConfig]) -> [AgentRun] {
        if agents.isEmpty {
            return inferAgentRuns(checkRuns: checkRuns, comments: comments)
        }

        return agents.map { agent in
            let matchingRuns = checkRuns.filter { matches(checkRun: $0, agent: agent) }
            let bestRun = latestRun(from: matchingRuns)
            let since = bestRun?.startedAt ?? bestRun?.createdAt ?? bestRun?.completedAt
            let commentCount = commentCountForAgent(agent: agent, comments: comments, since: since)

            guard let run = bestRun else {
                let status: AgentRunStatus = commentCount > 0 ? .done : .notFound
                return AgentRun(id: agent.id.uuidString, displayName: agent.displayName, status: status, commentCount: commentCount, checkConclusion: nil)
            }

            let status = agentStatus(run: run, commentCount: commentCount)
            return AgentRun(id: agent.id.uuidString, displayName: agent.displayName, status: status, commentCount: commentCount, checkConclusion: run.conclusion)
        }
    }

    private func inferAgentRuns(checkRuns: [CheckRunDTO], comments: [PRComment]) -> [AgentRun] {
        var seen: Set<String> = []
        var runs: [AgentRun] = []

        for run in checkRuns {
            let key = runKey(run)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let display = runDisplayName(run)

            let since = run.startedAt ?? run.createdAt ?? run.completedAt
            let commentCount = inferCommentCount(app: run.app, comments: comments, since: since)
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
        if commentCount > 0 {
            return .waitingForComment
        }
        return .done
    }

    private func commentCountForAgent(agent: AgentConfig, comments: [PRComment], since: Date?) -> Int {
        let filtered = filterComments(comments, since: since)
        let author = agent.commentAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
        if !author.isEmpty {
            let normalizedAuthor = normalize(author)
            return filtered.filter { normalize($0.author) == normalizedAuthor }.count
        }

        let normalized = normalize(agent.displayName)
        if normalized.isEmpty {
            return 0
        }
        return filtered.filter { normalize($0.author) == normalized }.count
    }

    private func inferCommentCount(app: CheckRunDTO.App?, comments: [PRComment], since: Date?) -> Int {
        guard let slug = app?.slug?.lowercased() else { return 0 }
        let filtered = filterComments(comments, since: since)
        return filtered.filter { normalize($0.author).hasPrefix(slug) }.count
    }

    private func latestRun(from runs: [CheckRunDTO]) -> CheckRunDTO? {
        runs.max(by: { runDate($0) < runDate($1) })
    }

    private func runDate(_ run: CheckRunDTO) -> Date {
        let candidates = [run.startedAt, run.completedAt, run.createdAt].compactMap { $0 }
        return candidates.max() ?? .distantPast
    }

    private func filterComments(_ comments: [PRComment], since: Date?) -> [PRComment] {
        guard let since else { return comments }
        return comments.filter { $0.createdAt >= since }
    }

    private func normalize(_ value: String) -> String {
        let lowered = value.lowercased()
        let removedBot = lowered.replacingOccurrences(of: "[bot]", with: "")
        let allowed = removedBot.filter { $0.isLetter || $0.isNumber }
        return allowed
    }

    private func runKey(_ run: CheckRunDTO) -> String {
        let appKey = run.app?.slug ?? run.app?.name ?? ""
        return "\(appKey.lowercased())::\(run.name.lowercased())"
    }

    private func runDisplayName(_ run: CheckRunDTO) -> String {
        let appName = run.app?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let runName = run.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appName.isEmpty else { return runName }
        if appName.caseInsensitiveCompare(runName) == .orderedSame {
            return appName
        }
        if runName.isEmpty {
            return appName
        }
        return "\(appName) — \(runName)"
    }
}
