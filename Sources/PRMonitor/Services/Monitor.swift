import Foundation
import Observation

/// Owns the polling loop and the current picture of every monitored pull request.
///
/// Data flow, one direction only:
/// `PullRequestFetcher` (network) → raw `PullRequest`s → `StatusEngine` (pure) → `PullRequestReport`s
/// → views, and → `NotificationPlanner` (pure) → `Notifier`.
@Observable
@MainActor
final class Monitor {
    struct Section: Identifiable, Hashable {
        let repository: RepositoryID
        var reports: [PullRequestReport]
        var totalOpen: Int
        /// Set when the last poll failed for this repository; `reports` then holds the last good data.
        var error: GitHubError?

        var id: RepositoryID { repository }
    }

    /// What the menu bar icon should convey, most urgent first.
    enum Summary: Equatable {
        case signedOut
        case needsRepositories
        case unavailable(GitHubError)
        case failing
        case needsReview
        case running
        case ready
        case idle
    }

    private(set) var sections: [Section] = []
    private(set) var lastUpdated: Date?
    private(set) var isRefreshing = false
    private(set) var lastError: GitHubError?

    let settings: AppSettings
    let account: Account
    private let notifier: Notifier
    private let fetcher = PullRequestFetcher()
    private let system = SystemEvents()

    @ObservationIgnored private var planner = NotificationPlanner()
    @ObservationIgnored private var pullRequests: [RepositoryID: (items: [PullRequest], totalOpen: Int)] = [:]
    @ObservationIgnored private var repositoryErrors: [RepositoryID: GitHubError] = [:]
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    @ObservationIgnored private var observerTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var isRefreshQueued = false
    @ObservationIgnored private var consecutiveFailures = 0

    /// How long to wait when there's nothing to do until something changes (sign-in, settings, network).
    private let dormantDelay: TimeInterval = 3600

    init(settings: AppSettings, account: Account, notifier: Notifier) {
        self.settings = settings
        self.account = account
        self.notifier = notifier
    }

    // MARK: - Lifecycle

    func start() {
        guard loopTask == nil else { return }
        notifier.activate()
        system.start { [weak self] in
            // Give Wi-Fi a moment to reassociate after wake before hitting the network.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.refresh()
            }
        }
        observeConfiguration()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = await self?.poll() else { return }
                await self?.sleep(for: delay)
            }
        }
    }

    /// Polls now. Coalesces with a poll that's already in flight rather than starting a second one.
    func refresh() {
        if isRefreshing {
            isRefreshQueued = true
        } else {
            sleepTask?.cancel()
        }
    }

    /// Called when the menu bar panel opens: cached data shows instantly, and is refreshed if old.
    func refreshIfStale(maximumAge: TimeInterval = 30) {
        guard let lastUpdated, Date.now.timeIntervalSince(lastUpdated) < maximumAge else {
            refresh()
            return
        }
    }

    // MARK: - Derived state

    /// Sections filtered by the user's display preferences, with empty repositories removed.
    var visibleSections: [Section] {
        sections.compactMap { section in
            var section = section
            section.reports = section.reports.filter(isVisible)
            return section.reports.isEmpty && section.error == nil ? nil : section
        }
    }

    var visibleReports: [PullRequestReport] {
        visibleSections.flatMap(\.reports)
    }

    var attentionCount: Int {
        visibleReports.count { $0.status.needsAttention }
    }

    var summary: Summary {
        guard account.isSignedIn else { return .signedOut }
        guard !settings.enabledRepositories.isEmpty else { return .needsRepositories }
        let reports = visibleReports
        if let lastError, reports.isEmpty { return .unavailable(lastError) }
        let top = reports.map(\.status).max { $0.urgency < $1.urgency }
        return switch top {
        case .failing: .failing
        case .needsReview: .needsReview
        case .running: .running
        case .ready: .ready
        case .quiet, nil: .idle
        }
    }

    /// Bots and integrations seen on current PRs, offered as suggestions when configuring agents.
    /// Built from the raw signals so suggestions carry real logins and app slugs, not normalized keys.
    var discoveredAgents: [Agent] {
        var found: [String: Agent] = [:]
        func add(key: String, name: String, checkPattern: String = "", login: String = "") {
            var agent = found[key] ?? Agent(name: name)
            if agent.checkPattern.isEmpty { agent.checkPattern = checkPattern }
            if agent.login.isEmpty { agent.login = login }
            found[key] = agent
        }
        for pr in pullRequests.values.flatMap(\.items) {
            for check in pr.checks {
                let pattern: String = switch check.source {
                case let .checkRun(appName, appSlug): appSlug ?? appName ?? check.name
                case let .commitStatus(creator): creator ?? check.name
                }
                add(key: check.groupKey, name: check.groupDisplayName, checkPattern: pattern)
            }
            let bots = pr.requestedReviewers.filter(\.isBot).map(\.login)
                + pr.reviews.filter(\.isBot).map(\.author)
                + pr.threads.filter(\.isBot).map(\.author)
            for login in bots {
                add(key: Identity.normalize(login), name: StatusEngine.displayName(forLogin: login), login: login)
            }
        }
        return found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func isVisible(_ report: PullRequestReport) -> Bool {
        let pr = report.pullRequest
        if settings.hidesDrafts, pr.isDraft { return false }
        if settings.scope == .authored {
            guard let viewer = account.credential?.login, let author = pr.author else { return false }
            return Identity.normalize(viewer) == Identity.normalize(author)
        }
        return true
    }

    // MARK: - Polling

    /// Performs one poll and returns how long to wait before the next.
    private func poll() async -> TimeInterval {
        guard let credential = account.credential else {
            clear()
            return dormantDelay
        }
        let repositories = settings.enabledRepositories
        guard !repositories.isEmpty else {
            clear()
            return dormantDelay
        }
        guard system.isOnline else {
            lastError = .offline
            return dormantDelay // The network monitor wakes us when the connection returns.
        }

        isRefreshing = true
        defer {
            isRefreshing = false
        }

        var policy = PollingPolicy(activeInterval: settings.refreshInterval)
        if system.isConstrained { policy.activeInterval = max(policy.activeInterval, 300) }

        let result: PullRequestFetcher.Result
        do {
            result = try await fetcher.fetch(repositories, client: GitHubClient(token: credential.token))
        } catch .unauthorized {
            account.sessionExpired()
            await fetcher.reset()
            return dormantDelay
        } catch let .rateLimited(resetAt) {
            lastError = .rateLimited(resetAt: resetAt)
            return policy.delay(after: .rateLimited(resetAt: resetAt))
        } catch {
            consecutiveFailures += 1
            lastError = error
            return nextDelay(policy.delay(after: .failure(consecutive: consecutiveFailures)))
        }

        consecutiveFailures = 0
        lastError = nil
        lastUpdated = .now
        if let login = result.viewerLogin { account.update(login: login) }

        // Forget repositories that are no longer tracked; keep last good data for ones that failed.
        let tracked = Set(repositories)
        pullRequests = pullRequests.filter { tracked.contains($0.key) }
        repositoryErrors.removeAll()
        for (repository, outcome) in result.repositories {
            switch outcome {
            case let .loaded(items, totalOpen): pullRequests[repository] = (items, totalOpen)
            case let .failed(error): repositoryErrors[repository] = error
            }
        }
        rebuild()

        let planned = planner.plan(for: visibleReports, preferences: settings.notificationPreferences)
        await notifier.post(planned)

        // Leave headroom in the hourly budget for the user's other tools (gh, IDEs, scripts).
        if let limit = result.rateLimit, limit.remaining < 250 {
            return nextDelay(policy.delay(after: .rateLimited(resetAt: limit.resetAt)))
        }
        let reports = sections.flatMap(\.reports)
        return nextDelay(policy.delay(after: .success(
            hasRunningPullRequests: reports.contains { !$0.isSettled },
            hasOpenPullRequests: !reports.isEmpty
        )))
    }

    private func nextDelay(_ delay: TimeInterval) -> TimeInterval {
        guard isRefreshQueued else { return delay }
        isRefreshQueued = false
        return 0
    }

    /// Re-derives every report from the raw data. Cheap, so it also runs when agent settings change.
    private func rebuild() {
        let engine = settings.statusEngine
        let now = Date.now
        let repositories = Set(pullRequests.keys).union(repositoryErrors.keys)
        sections = repositories.sorted().map { repository in
            let data = pullRequests[repository]
            return Section(
                repository: repository,
                reports: (data?.items ?? []).map { engine.report(for: $0, now: now) },
                totalOpen: data?.totalOpen ?? 0,
                error: repositoryErrors[repository]
            )
        }
    }

    private func clear() {
        sections = []
        pullRequests = [:]
        repositoryErrors = [:]
        lastError = nil
        lastUpdated = nil
    }

    private func sleep(for seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        let task = Task { _ = try? await Task.sleep(for: .seconds(seconds)) }
        sleepTask = task
        await task.value
        sleepTask = nil
    }

    // MARK: - Reacting to configuration

    private struct FetchConfiguration: Equatable, Sendable {
        let token: String?
        let repositories: [RepositoryID]
        let interval: TimeInterval
    }

    private struct EngineConfiguration: Equatable, Sendable {
        let mode: AgentMode
        let agents: [Agent]
    }

    private func observeConfiguration() {
        // Anything that changes *what* we fetch triggers an immediate poll.
        observerTasks.append(Task { [weak self] in
            let changes = Observations { [weak self] in
                FetchConfiguration(
                    token: self?.account.credential?.token,
                    repositories: self?.settings.enabledRepositories ?? [],
                    interval: self?.settings.refreshInterval ?? 60
                )
            }
            var previous: FetchConfiguration?
            for await configuration in changes {
                defer { previous = configuration }
                guard let previous, previous != configuration else { continue }
                if previous.token != configuration.token { await self?.fetcher.reset() }
                self?.refresh()
            }
        })

        // Changes to how agents are interpreted only need a re-derivation, not a network round trip.
        observerTasks.append(Task { [weak self] in
            let changes = Observations { [weak self] in
                EngineConfiguration(mode: self?.settings.agentMode ?? .automatic, agents: self?.settings.agents ?? [])
            }
            var previous: EngineConfiguration?
            for await configuration in changes {
                defer { previous = configuration }
                guard previous != nil, previous != configuration else { continue }
                self?.rebuild()
            }
        })
    }
}

#if DEBUG
extension Monitor {
    /// Shows fixed data without polling, for previews and snapshots.
    func loadPreview(_ items: [PullRequest], updatedSecondsAgo: TimeInterval = 45) {
        pullRequests = Dictionary(grouping: items, by: \.repository).mapValues { ($0, $0.count) }
        rebuild()
        lastUpdated = .now.addingTimeInterval(-updatedSecondsAgo)
    }
}
#endif
