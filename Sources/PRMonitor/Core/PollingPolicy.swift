import Foundation

/// Decides how long to wait before the next poll.
struct PollingPolicy: Sendable {
    enum Outcome: Sendable {
        case success(hasRunningPullRequests: Bool, hasOpenPullRequests: Bool)
        case rateLimited(resetAt: Date?)
        case failure(consecutive: Int)
    }

    /// The user's chosen interval, used while any agent is still working.
    var activeInterval: TimeInterval
    /// Used when every open PR has settled; pushes and new feedback are still picked up.
    var settledInterval: TimeInterval = 120
    /// Used when there are no open PRs at all.
    var idleInterval: TimeInterval = 300
    var maximumBackoff: TimeInterval = 600

    func delay(after outcome: Outcome, now: Date = .now) -> TimeInterval {
        switch outcome {
        case let .success(running, open):
            if running { return activeInterval }
            return open ? max(activeInterval, settledInterval) : max(activeInterval, idleInterval)
        case let .rateLimited(resetAt):
            // Wait out the window, plus a little slack so we don't land a hair early.
            let wait = (resetAt?.timeIntervalSince(now) ?? 60) + 5
            return min(max(wait, 30), 3600)
        case let .failure(consecutive):
            // 30s, 60s, 120s … capped. Transient network blips recover quickly; outages don't hammer.
            let exponent = Double(max(0, consecutive - 1))
            return min(30 * pow(2, exponent), maximumBackoff)
        }
    }
}
