#if DEBUG
import Foundation

/// `PRMonitor --diagnose owner/repo [owner/repo …]` runs the real fetcher and status engine against
/// live GitHub data using the GitHub CLI's token, prints what the menu bar would show, and exits.
/// Useful for checking status derivation against your own repositories. Debug builds only.
enum Diagnostics {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--diagnose") else { return }
        let repositories = arguments[(index + 1)...].compactMap(RepositoryID.init(parsing:))

        let done = DispatchSemaphore(value: 0)
        Task.detached {
            await run(repositories)
            done.signal()
        }
        done.wait()
        exit(0)
    }

    private static func run(_ repositories: [RepositoryID]) async {
        guard !repositories.isEmpty else {
            print("usage: PRMonitor --diagnose owner/repo [owner/repo …]")
            return
        }
        do {
            let client = GitHubClient(token: try await GitHubCLI.token())
            let fetcher = PullRequestFetcher()
            let clock = ContinuousClock()

            let start = clock.now
            let result = try await fetcher.fetch(repositories, client: client)
            let firstPoll = clock.now - start

            let secondStart = clock.now
            _ = try await fetcher.fetch(repositories, client: client)
            let secondPoll = clock.now - secondStart

            let engine = StatusEngine(mode: .automatic, agents: [])
            print("Viewer: \(result.viewerLogin ?? "?")  ·  rate limit remaining: \(result.rateLimit?.remaining ?? -1)")
            print("First poll \(firstPoll.formatted(.units(allowed: [.milliseconds]))), cached poll \(secondPoll.formatted(.units(allowed: [.milliseconds])))\n")

            for repository in repositories {
                switch result.repositories[repository] {
                case let .loaded(pullRequests, totalOpen):
                    print("■ \(repository)  (\(totalOpen) open)")
                    for pr in pullRequests {
                        let report = engine.report(for: pr)
                        let flags = [pr.isDraft ? "draft" : nil, pr.mergeable == .conflicting ? "conflicts" : nil].compactMap(\.self)
                        print("  #\(pr.number) [\(report.status.title)\(report.isSettled ? "" : ", running")] \(pr.title.prefix(60))\(flags.isEmpty ? "" : "  (\(flags.joined(separator: ", ")))")")
                        for agent in report.agents {
                            print("      · \(agent.name): \(agent.state) — \(agent.summary)")
                        }
                    }
                case let .failed(error):
                    print("■ \(repository)  ✕ \(error.localizedDescription)")
                case nil:
                    print("■ \(repository)  (no result)")
                }
            }
        } catch {
            print("Diagnostics failed: \(error.localizedDescription)")
        }
    }
}
#endif
