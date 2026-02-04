import Foundation
import Combine
import UserNotifications

@MainActor
final class AppState: ObservableObject {
    enum OverallStatus {
        case needsAuth
        case idle
        case running
        case waiting
        case done
    }

    @Published var repoSections: [RepoSection] = []
    @Published var lastRefresh: Date?
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published var viewerLogin: String?

    let settingsStore: SettingsStore
    let authStore: AuthStore

    private let pollingService: PollingService
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastAllDone = false
    private var activeInterval: TimeInterval?
    private let idleIntervalSeconds: TimeInterval = 600
    private var lastAgentStatus: [String: AgentRunStatus] = [:]

    init(settingsStore: SettingsStore, authStore: AuthStore) {
        self.settingsStore = settingsStore
        self.authStore = authStore
        let client = GitHubClient(tokenProvider: { authStore.token })
        self.pollingService = PollingService(client: client)

        settingsStore.$pollingIntervalSeconds
            .sink { [weak self] _ in self?.restartPolling() }
            .store(in: &cancellables)

        settingsStore.$repos
            .sink { [weak self] _ in self?.restartPolling() }
            .store(in: &cancellables)

        authStore.$token
            .sink { [weak self] _ in self?.restartPolling() }
            .store(in: &cancellables)

        requestNotificationPermissions()
        restartPolling()
    }

    var overallStatus: OverallStatus {
        guard authStore.isSignedIn else { return .needsAuth }
        let agents = repoSections.flatMap { $0.prs.flatMap { $0.agents } }
        if agents.isEmpty { return .idle }
        if agents.contains(where: { $0.status == .running }) { return .running }
        if agents.contains(where: { $0.status == .waitingForComment || $0.status == .notFound }) { return .waiting }
        return .done
    }

    func refreshNow() {
        guard authStore.isSignedIn else {
            repoSections = []
            updateTimerInterval(hasOpenPRs: false)
            return
        }
        let repos = settingsStore.enabledRepos
        guard !repos.isEmpty else {
            repoSections = []
            updateTimerInterval(hasOpenPRs: false)
            return
        }

        isRefreshing = true
        errorMessage = nil

        Task {
            do {
                let sections = try await pollingService.fetchRepoSections(repos: repos, agents: settingsStore.agents)
                repoSections = sections.filter { !$0.prs.isEmpty }
                lastRefresh = Date()
                await updateViewerLogin()
                handleNotificationsIfNeeded()
                updateTimerInterval(hasOpenPRs: !repoSections.isEmpty)
            } catch {
                errorMessage = error.localizedDescription
            }
            isRefreshing = false
        }
    }

    func restartPolling() {
        timer?.invalidate()
        timer = nil
        activeInterval = nil
        refreshNow()
        updateTimerInterval(hasOpenPRs: !repoSections.isEmpty)
    }

    private func handleNotificationsIfNeeded() {
        guard notificationsAvailable else { return }
        let allDone = overallStatus == .done
        if allDone && !lastAllDone {
            sendAllDoneNotification()
        }
        lastAllDone = allDone
        handlePerAgentNotifications()
    }

    private func sendAllDoneNotification() {
        guard notificationsAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = "PR Monitor"
        content.body = "All agents have completed their checks and comments."
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func handlePerAgentNotifications() {
        guard notificationsAvailable else { return }
        guard settingsStore.notifyPerAgent else { return }

        var nextStatus: [String: AgentRunStatus] = [:]
        for section in repoSections {
            for pr in section.prs {
                for agent in pr.agents {
                    let key = "\(section.fullName)#\(pr.number)#\(agent.id)"
                    nextStatus[key] = agent.status
                    if agent.status == .done && lastAgentStatus[key] != .done {
                        sendAgentDoneNotification(pr: pr, agent: agent)
                    }
                }
            }
        }
        lastAgentStatus = nextStatus
    }

    private func sendAgentDoneNotification(pr: PRItem, agent: AgentRun) {
        guard notificationsAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = "PR Monitor"
        content.body = "\(agent.displayName) finished on #\(pr.number) \(pr.title)."
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func requestNotificationPermissions() {
        guard notificationsAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func updateViewerLogin() async {
        do {
            viewerLogin = try await pollingService.client.fetchViewerLogin()
        } catch {
            viewerLogin = nil
        }
    }

    private var notificationsAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private func updateTimerInterval(hasOpenPRs: Bool) {
        guard authStore.isSignedIn else {
            activeInterval = nil
            timer?.invalidate()
            timer = nil
            return
        }
        guard !settingsStore.enabledRepos.isEmpty else {
            activeInterval = nil
            timer?.invalidate()
            timer = nil
            return
        }
        let targetInterval: TimeInterval
        if hasOpenPRs {
            targetInterval = TimeInterval(max(30, settingsStore.pollingIntervalSeconds))
        } else {
            targetInterval = idleIntervalSeconds
        }

        guard activeInterval != targetInterval else { return }
        activeInterval = targetInterval
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: targetInterval, repeats: true) { [weak self] _ in
            self?.refreshNow()
        }
    }
}
