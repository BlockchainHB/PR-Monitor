#if DEBUG
import AppKit
import SwiftUI

/// Fictional pull requests for SwiftUI previews and README screenshots. Never real repository data.
enum PreviewData {
    static let now = Date.now

    static let pullRequests: [PullRequest] = [
        pr(1, "acme/rocket", 482, "Add retry budget to the launch sequencer", author: "hasaam", minutesAgo: 3,
           checks: [
               check("build", "GitHub Actions", "github-actions", .succeeded),
               check("test", "GitHub Actions", "github-actions", .succeeded),
               check("Cursor Bugbot", "Cursor", "cursor", .succeeded),
               status("Vercel", "vercel", .succeeded),
           ],
           reviews: [review("cursor", .commented)],
           threads: [thread("cursor"), thread("cursor"), thread("chatgpt-codex-connector")]),
        pr(2, "acme/rocket", 479, "Migrate telemetry to structured events", author: "mei", minutesAgo: 12,
           checks: [
               check("build", "GitHub Actions", "github-actions", .succeeded),
               check("test", "GitHub Actions", "github-actions", .pending),
               check("Cursor Bugbot", "Cursor", "cursor", .pending),
           ],
           requested: [ReviewRequestSignal(login: "copilot-pull-request-reviewer", isBot: true)]),
        pr(3, "acme/rocket", 471, "Fix race in fuel gauge updates", author: "hasaam", minutesAgo: 45,
           checks: [
               check("build", "GitHub Actions", "github-actions", .failed, raw: "FAILURE"),
               check("lint", "GitHub Actions", "github-actions", .succeeded),
               status("Vercel", "vercel", .succeeded),
           ]),
        pr(4, "acme/mission-control", 118, "Dark mode for the flight dashboard", author: "jordan", minutesAgo: 90,
           checks: [
               check("CI", "GitHub Actions", "github-actions", .succeeded),
               status("Vercel", "vercel", .succeeded),
               check("Devin Review", "Devin", "devin-ai-integration", .succeeded),
           ],
           reviews: [review("devin-ai-integration", .approved)], decision: .approved),
        pr(5, "acme/mission-control", 116, "Prototype orbit planner", author: "sam", minutesAgo: 60 * 26,
           isDraft: true, mergeable: .conflicting,
           checks: [check("CI", "GitHub Actions", "github-actions", .succeeded)]),
    ]

    @MainActor
    static func environment() -> (AppSettings, Account, Monitor, AppRouter) {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "PRMonitor.preview")!)
        settings.repositories = [
            TrackedRepository(id: RepositoryID(owner: "acme", name: "rocket")),
            TrackedRepository(id: RepositoryID(owner: "acme", name: "mission-control")),
        ]
        settings.scope = .all
        settings.hidesDrafts = false
        let account = Account(previewLogin: "hasaam")
        let monitor = Monitor(settings: settings, account: account, notifier: Notifier())
        monitor.loadPreview(pullRequests)
        return (settings, account, monitor, AppRouter())
    }

    // MARK: - Builders

    private static func pr(
        _ id: Int, _ repo: String, _ number: Int, _ title: String, author: String, minutesAgo: Double,
        isDraft: Bool = false, mergeable: Mergeable = .mergeable, checks: [CheckSignal] = [],
        requested: [ReviewRequestSignal] = [], reviews: [ReviewSignal] = [], threads: [ThreadSignal] = [],
        decision: ReviewDecision? = nil
    ) -> PullRequest {
        let repository = RepositoryID(parsing: repo)!
        return PullRequest(
            id: "PREVIEW_\(id)", repository: repository, number: number, title: title,
            url: URL(string: "https://github.com/\(repo)/pull/\(number)")!, author: author, isDraft: isDraft,
            createdAt: now.addingTimeInterval(-86_400), updatedAt: now.addingTimeInterval(-minutesAgo * 60),
            headSHA: "head\(id)", headCommittedAt: now.addingTimeInterval(-max(minutesAgo, 20) * 60), rollupState: nil,
            reviewDecision: decision, mergeable: mergeable, checks: checks, requestedReviewers: requested,
            reviews: reviews, threads: threads, comments: []
        )
    }

    private static func check(_ name: String, _ app: String, _ slug: String, _ outcome: CheckSignal.Outcome, raw: String? = nil) -> CheckSignal {
        CheckSignal(name: name, source: .checkRun(appName: app, appSlug: slug), outcome: outcome,
                    rawState: raw ?? (outcome == .pending ? "IN_PROGRESS" : "SUCCESS"),
                    startedAt: now.addingTimeInterval(-600), completedAt: outcome == .pending ? nil : now.addingTimeInterval(-240), url: nil)
    }

    private static func status(_ context: String, _ creator: String, _ outcome: CheckSignal.Outcome) -> CheckSignal {
        CheckSignal(name: context, source: .commitStatus(creator: creator), outcome: outcome, rawState: "SUCCESS",
                    startedAt: now.addingTimeInterval(-500), completedAt: now.addingTimeInterval(-420), url: nil)
    }

    private static func review(_ login: String, _ state: ReviewSignal.State) -> ReviewSignal {
        ReviewSignal(author: login, isBot: true, state: state, submittedAt: now.addingTimeInterval(-300), commitSHA: nil)
    }

    private static func thread(_ login: String) -> ThreadSignal {
        ThreadSignal(author: login, isBot: true, isResolved: false, isOutdated: false, createdAt: now.addingTimeInterval(-280))
    }
}

/// `PRMonitor --settings-window <tab>` shows the real Settings window (with its toolbar) on
/// preview data and prints its window number, so it can be captured with `screencapture -l`.
enum SettingsWindowPreview {
    @MainActor private static var window: NSWindow?

    @MainActor
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--settings-window") else { return }
        let name = arguments.indices.contains(index + 1) ? arguments[index + 1] : "account"
        let tab: AppRouter.SettingsTab = switch name {
        case "general": .general
        case "notifications": .notifications
        case "repositories": .repositories
        case "agents": .agents
        default: .account
        }
        Task { @MainActor in
            let (settings, account, monitor, router) = PreviewData.environment()
            router.settingsTab = tab
            let host = NSHostingController(rootView: SettingsView()
                .environment(monitor).environment(settings).environment(account).environment(router))
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.title = "Settings"
            window.setContentSize(NSSize(width: 760, height: 540))
            window.center()
            window.level = .floating // Visible for capture even when another app is frontmost.
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            self.window = window
            try? await Task.sleep(for: .seconds(1))
            let frame = window.frame, screen = window.screen?.frame.height ?? 0
            print("WINDOW \(Int(frame.minX)),\(Int(screen - frame.maxY)),\(Int(frame.width)),\(Int(frame.height))")
            fflush(stdout)
            try? await Task.sleep(for: .seconds(4))
            exit(0)
        }
    }
}

/// `PRMonitor --snapshot <directory>` renders the panel with preview data to PNGs, in light and dark.
enum Snapshots {
    @MainActor
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1) else { return }
        let directory = URL(filePath: arguments[index + 1], directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let (settings, account, monitor, router) = PreviewData.environment()
        let expandedID = PreviewData.pullRequests[0].id
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            render(
                MenuBarPanel(initiallyExpanded: [expandedID])
                    .environment(monitor).environment(settings).environment(account).environment(router),
                appearance: appearance,
                to: directory.appending(path: "panel-\(name).png")
            )
        }
        renderIcons(to: directory.appending(path: "menu-bar-icons.png"))

        let loadingMonitor = Monitor(settings: settings, account: account, notifier: Notifier())
        render(
            MenuBarPanel().environment(loadingMonitor).environment(settings).environment(account).environment(router),
            appearance: .aqua, to: directory.appending(path: "panel-loading.png")
        )

        let signedOut = Account(previewSignedOut: ())
        let onboardingMonitor = Monitor(settings: settings, account: signedOut, notifier: Notifier())
        render(
            MenuBarPanel().environment(onboardingMonitor).environment(settings).environment(signedOut).environment(router),
            appearance: .aqua, to: directory.appending(path: "panel-onboarding.png")
        )

        let tabs: [(String, AppRouter.SettingsTab)] = [
            ("account", .account), ("general", .general), ("notifications", .notifications), ("repositories", .repositories), ("agents", .agents),
        ]
        for (name, tab) in tabs {
            router.settingsTab = tab
            render(
                SettingsView().environment(monitor).environment(settings).environment(account).environment(router),
                appearance: .aqua, to: directory.appending(path: "settings-\(name).png")
            )
        }
        exit(0)
    }

    /// Every menu bar state, template and colored, on light and dark bars, scaled up 4×.
    @MainActor
    private static func renderIcons(to url: URL) {
        let states: [(Monitor.Summary, Int)] = [(.signedOut, 0), (.idle, 0), (.running, 0), (.needsReview, 0), (.ready, 0), (.needsReview, 2), (.failing, 12)]
        let scale: CGFloat = 4, cell = NSSize(width: 40, height: 22)
        let size = NSSize(width: cell.width * CGFloat(states.count) * scale, height: cell.height * 4 * scale)
        let image = NSImage(size: size, flipped: true) { _ in
            for (row, (dark, colored)) in [(false, false), (true, false), (false, true), (true, true)].enumerated() {
                let background = dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1)
                background.setFill()
                NSRect(x: 0, y: CGFloat(row) * cell.height * scale, width: size.width, height: cell.height * scale).fill()
                NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
                    for (column, (state, count)) in states.enumerated() {
                        let icon = StatusIcon.image(for: state, count: count, isColored: colored)
                        let rect = NSRect(
                            x: (CGFloat(column) * cell.width + (cell.width - icon.size.width) / 2) * scale,
                            y: (CGFloat(row) * cell.height + (cell.height - icon.size.height) / 2) * scale,
                            width: icon.size.width * scale, height: icon.size.height * scale
                        )
                        let drawn = colored ? icon : tint(icon, dark ? .white : .black)
                        drawn.draw(in: rect)
                    }
                }
            }
            return true
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func tint(_ template: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: template.size, flipped: false) { rect in
            template.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    @MainActor
    private static func render(_ view: some View, appearance: NSAppearance.Name, to url: URL) {
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: appearance)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: .now.addingTimeInterval(0.3))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

#Preview("Panel") {
    let (settings, account, monitor, router) = PreviewData.environment()
    MenuBarPanel()
        .environment(monitor).environment(settings).environment(account).environment(router)
}
#endif
