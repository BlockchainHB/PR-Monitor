import Foundation

/// Loads open pull requests for many repositories with as few GraphQL points as possible.
///
/// Holds a cache of PR details between polls. Each poll lists every repository (cheap), then
/// re-fetches details only for PRs that changed, still have work in flight, or went stale.
actor PullRequestFetcher {
    struct Result: Sendable {
        var viewerLogin: String?
        var repositories: [RepositoryID: RepositoryResult]
        /// Remaining GraphQL points and when the window resets, for pacing the next poll.
        var rateLimit: (remaining: Int, resetAt: Date)?
    }

    enum RepositoryResult: Sendable {
        case loaded(pullRequests: [PullRequest], totalOpen: Int)
        case failed(GitHubError)
    }

    private struct CacheEntry {
        let fingerprint: String
        let fetchedAt: Date
        let pullRequest: PullRequest
    }

    private var cache: [String: CacheEntry] = [:]
    private let repositoriesPerListQuery = 10
    /// Details are refreshed at least this often even if nothing appears to have changed, which
    /// catches events that don't bump `updatedAt` (e.g. a thread being resolved).
    private let maximumDetailAge: TimeInterval = 300
    /// Right after a push, agents are still registering; keep details fresh during that window.
    private let recentPushWindow: TimeInterval = 600

    func reset() {
        cache.removeAll()
    }

    func fetch(_ repositories: [RepositoryID], client: GitHubClient, now: Date = .now) async throws(GitHubError) -> Result {
        guard !repositories.isEmpty else { return Result(viewerLogin: nil, repositories: [:], rateLimit: nil) }

        // Phase 1: list every repository, batched with aliases.
        let batches = stride(from: 0, to: repositories.count, by: repositoriesPerListQuery).map {
            Array(repositories[$0..<min($0 + repositoriesPerListQuery, repositories.count)])
        }
        var viewerLogin: String?
        var rateLimit: (remaining: Int, resetAt: Date)?
        var listed: [RepositoryID: (items: [PullRequestQueries.ListItemDTO], total: Int)] = [:]
        var failures: [RepositoryID: GitHubError] = [:]

        for batch in batches {
            let response = try await retryingServerErrors { () async throws(GitHubError) in
                try await client.query(
                    PullRequestQueries.listDocument(repositoryCount: batch.count),
                    variables: PullRequestQueries.listVariables(for: batch),
                    as: PullRequestQueries.ListPayload.self
                )
            }
            viewerLogin = viewerLogin ?? response.data?.viewerLogin
            if let limit = response.data?.rateLimit { rateLimit = (limit.remaining, limit.resetAt) }
            let errorsByAlias = Dictionary(grouping: response.errors, by: { $0.rootField ?? "" })
            for (index, repository) in batch.enumerated() {
                let alias = "r\(index)"
                if let dto = response.data?.repositories[alias] ?? nil {
                    listed[repository] = (dto.pullRequests.nodes, dto.pullRequests.totalCount)
                } else {
                    let error = errorsByAlias[alias]?.first
                    failures[repository] = error?.type == "NOT_FOUND"
                        ? .notFound("Repository not found, or your account can't access it.")
                        : .graphQL([error?.message ?? "Couldn't load this repository."])
                }
            }
        }

        // Phase 2: fetch details for PRs that need them.
        let allItems = listed.values.flatMap(\.items)
        let staleIDs = allItems.filter { needsDetail($0, now: now) }.map(\.id)
        let fingerprints = Dictionary(allItems.map { ($0.id, $0.fingerprint) }, uniquingKeysWith: { a, _ in a })

        for start in stride(from: 0, to: staleIDs.count, by: PullRequestQueries.detailBatchSize) {
            let ids = Array(staleIDs[start..<min(start + PullRequestQueries.detailBatchSize, staleIDs.count)])
            let response = try await retryingServerErrors { () async throws(GitHubError) in
                try await client.query(
                    PullRequestQueries.detailDocument,
                    variables: ["ids": .strings(ids)],
                    as: PullRequestQueries.DetailPayload.self
                )
            }
            for dto in response.data?.nodes ?? [] {
                guard let dto else { continue }
                cache[dto.id] = CacheEntry(fingerprint: fingerprints[dto.id] ?? "", fetchedAt: now, pullRequest: dto.toPullRequest())
            }
        }

        // Drop PRs that are no longer open so the cache can't grow without bound.
        let liveIDs = Set(allItems.map(\.id))
        cache = cache.filter { liveIDs.contains($0.key) }

        var results: [RepositoryID: RepositoryResult] = failures.mapValues { .failed($0) }
        for (repository, listing) in listed {
            let pullRequests = listing.items.compactMap { cache[$0.id]?.pullRequest }
            results[repository] = .loaded(pullRequests: pullRequests, totalOpen: listing.total)
        }
        return Result(viewerLogin: viewerLogin, repositories: results, rateLimit: rateLimit)
    }

    /// GitHub's GraphQL gateway occasionally returns 502/504 for heavy queries; one retry after a
    /// short pause almost always succeeds.
    private func retryingServerErrors<T: Sendable>(
        _ operation: () async throws(GitHubError) -> T
    ) async throws(GitHubError) -> T {
        do {
            return try await operation()
        } catch .server {
            try? await Task.sleep(for: .seconds(1))
            return try await operation()
        }
    }

    private func needsDetail(_ item: PullRequestQueries.ListItemDTO, now: Date) -> Bool {
        guard let entry = cache[item.id] else { return true }
        if entry.fingerprint != item.fingerprint { return true }
        if item.hasPendingChecks { return true }
        if now.timeIntervalSince(entry.fetchedAt) > maximumDetailAge { return true }
        let pr = entry.pullRequest
        if !pr.requestedReviewers.filter(\.isBot).isEmpty { return true }
        if let pushed = pr.headCommittedAt, now.timeIntervalSince(pushed) < recentPushWindow { return true }
        return false
    }
}
