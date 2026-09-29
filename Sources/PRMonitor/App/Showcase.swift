#if DEBUG
import AppKit
import SwiftUI

/// `PRMonitor --showcase <scene>` puts marketing compositions on screen, built from the real views on
/// real Liquid Glass over a designed backdrop, then prints the rect to capture with `screencapture -R`.
/// Scenes: `hero-dark`, `hero-light`, `settings-dark`, `settings-light`. Debug builds only.
enum Showcase {
    @MainActor private static var windows: [NSWindow] = []

    @MainActor
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--showcase"), arguments.indices.contains(index + 1) else { return }
        let scene = arguments[index + 1]
        let isDark = scene.hasSuffix("dark")

        Task { @MainActor in
            let (settings, account, monitor, router) = PreviewData.environment()
            let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
            let canvas = NSSize(width: 1280, height: 800)
            guard let screen = NSScreen.main else { return }
            let origin = NSPoint(x: screen.frame.midX - canvas.width / 2, y: screen.frame.midY - canvas.height / 2)
            let frame = NSRect(origin: origin, size: canvas)

            if scene.hasPrefix("hero") {
                let hero = HeroComposition(isDark: isDark, expandedID: PreviewData.pullRequests[0].id)
                    .environment(monitor).environment(settings).environment(account).environment(router)
                show(hero, frame: frame, appearance: appearance, level: .floating)
            } else {
                show(Backdrop(isDark: isDark), frame: frame, appearance: appearance, level: .floating)
                router.settingsTab = .agents
                let settingsWindow = AlwaysKeyWindow(
                    contentViewController: NSHostingController(rootView: SettingsView()
                        .environment(monitor).environment(settings).environment(account).environment(router))
                )
                settingsWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
                settingsWindow.title = "Agents"
                settingsWindow.appearance = appearance
                settingsWindow.setContentSize(NSSize(width: 760, height: 520))
                settingsWindow.setFrameOrigin(NSPoint(x: frame.midX - 380, y: frame.midY - 280))
                settingsWindow.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
                // Active, so traffic lights and controls render in their key-window colors.
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                settingsWindow.makeKeyAndOrderFront(nil)
                windows.append(settingsWindow)
            }

            // macOS may decline the first activation request from a background launch; ask again.
            for _ in 0..<4 {
                try? await Task.sleep(for: .seconds(0.5))
                if !NSApp.isActive {
                    NSRunningApplication.current.activate(options: [.activateAllWindows])
                    windows.last?.makeKeyAndOrderFront(nil)
                }
            }
            try? await Task.sleep(for: .seconds(0.5))
            let top = screen.frame.height - frame.maxY
            print("RECT \(Int(frame.minX)),\(Int(top)),\(Int(frame.width)),\(Int(frame.height))")
            fflush(stdout)
            try? await Task.sleep(for: .seconds(5))
            exit(0)
        }
    }

    @MainActor
    private static func show(_ view: some View, frame: NSRect, appearance: NSAppearance?, level: NSWindow.Level) {
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: view)
        window.appearance = appearance
        window.level = level
        window.hasShadow = false
        window.orderFrontRegardless()
        windows.append(window)
    }
}

/// Draws with the active (key) appearance even though a background-launched app can't take focus
/// from whatever the user is doing, so captures don't show gray traffic lights and controls.
private final class AlwaysKeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}

// MARK: - Compositions

/// A soft, Tahoe-style mesh-gradient wallpaper, so Liquid Glass has color to refract.
private struct Backdrop: View {
    let isDark: Bool

    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.62, 0.45], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: isDark ? [
                Color(red: 0.05, green: 0.07, blue: 0.16), Color(red: 0.10, green: 0.10, blue: 0.30), Color(red: 0.20, green: 0.10, blue: 0.34),
                Color(red: 0.03, green: 0.20, blue: 0.22), Color(red: 0.08, green: 0.30, blue: 0.40), Color(red: 0.30, green: 0.14, blue: 0.40),
                Color(red: 0.02, green: 0.12, blue: 0.10), Color(red: 0.04, green: 0.26, blue: 0.20), Color(red: 0.10, green: 0.14, blue: 0.30),
            ] : [
                Color(red: 0.80, green: 0.87, blue: 1.00), Color(red: 0.88, green: 0.84, blue: 1.00), Color(red: 0.98, green: 0.86, blue: 0.94),
                Color(red: 0.74, green: 0.93, blue: 0.92), Color(red: 0.80, green: 0.90, blue: 1.00), Color(red: 0.95, green: 0.84, blue: 0.96),
                Color(red: 0.78, green: 0.95, blue: 0.86), Color(red: 0.72, green: 0.90, blue: 0.95), Color(red: 0.86, green: 0.86, blue: 1.00),
            ]
        )
    }
}

/// The hero: the panel on real Liquid Glass hanging from a menu bar, with the icon and a headline.
private struct HeroComposition: View {
    let isDark: Bool
    let expandedID: String
    @Environment(Monitor.self) private var monitor

    /// The default (light) rendition exported from Icon Composer, so marketing shots always show the
    /// canonical icon regardless of the Mac's icon style setting.
    static let marketingIcon: NSImage = {
        let repository = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return NSImage(contentsOf: repository.appending(path: "docs/screenshots/app-icon.png")) ?? NSApp.applicationIconImage
    }()

    var body: some View {
        ZStack(alignment: .top) {
            Backdrop(isDark: isDark)

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 18) {
                    Image(nsImage: Self.marketingIcon)
                        .resizable()
                        .frame(width: 112, height: 112)
                        .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
                    Text("Know the moment\nyour pull request\nis ready.")
                        .font(.system(size: 50, weight: .bold, design: .default))
                        .tracking(-0.8)
                        .foregroundStyle(.primary)
                    Text("Every CI check and AI reviewer on your PRs, in one glance from the menu bar.")
                        .font(.system(size: 19))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 420, alignment: .leading)
                }
                .padding(.leading, 80)
                .padding(.top, 170)
                Spacer()
                MenuBarPanel(initiallyExpanded: [expandedID])
                    .glassEffect(.regular, in: .rect(cornerRadius: Metrics.panelCornerRadius))
                    .shadow(color: .black.opacity(isDark ? 0.45 : 0.18), radius: 30, y: 18)
                    .padding(.top, 44)
                    .padding(.trailing, 150)
            }

            MockMenuBar(summary: monitor.summary, count: monitor.attentionCount, isDark: isDark)
        }
        .frame(width: 1280, height: 800)
        .clipped()
    }
}

/// A slim stand-in for the macOS menu bar showing PR Monitor's real status icon, positioned so the
/// panel hangs beneath it.
private struct MockMenuBar: View {
    let summary: Monitor.Summary
    let count: Int
    let isDark: Bool

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "apple.logo").font(.system(size: 15, weight: .medium))
            Text("Finder").fontWeight(.bold)
            Text("File")
            Text("Edit")
            Text("View")
            Spacer()
            Image(nsImage: StatusIcon.image(for: summary, count: count, isColored: false))
                .renderingMode(.template)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(.primary.opacity(0.14)))
                .padding(.trailing, 268)
                .overlay(alignment: .trailing) {
                    HStack(spacing: 18) {
                        Image(systemName: "wifi")
                        Image(systemName: "battery.75percent")
                        Image(systemName: "switch.2")
                        Text("Mon Sep 28  9:41 AM")
                    }
                }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 18)
        .frame(height: 30)
    }
}
#endif

#if DEBUG
/// `PRMonitor --portfolio <directory>` renders the menu bar panel for a portfolio site: transparent
/// PNGs at exactly 2 px per point, cropped to the panel edge, with no shadow, in light and dark,
/// with the first two pull requests expanded, plus a fully expanded variant. Uses fictional
/// repositories. Debug builds only.
enum PortfolioShots {
    @MainActor
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--portfolio"), arguments.indices.contains(index + 1) else { return }
        let directory = URL(filePath: arguments[index + 1], directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let (settings, account, monitor, router) = PreviewData.environment()
        // Minute-granular "Updated 2 minutes ago" can't tick between the light and dark renders.
        monitor.loadPreview(PortfolioData.pullRequests, updatedSecondsAgo: 150)
        let primary = Set(PortfolioData.pullRequests.prefix(2).map(\.id))
        let everything = Set(PortfolioData.pullRequests.map(\.id))

        func panel(_ expanded: Set<String>) -> some View {
            MenuBarPanel(initiallyExpanded: expanded)
                .environment(monitor).environment(settings).environment(account).environment(router)
                .background(PanelSurface())
                .clipShape(.rect(cornerRadius: Metrics.panelCornerRadius, style: .continuous))
        }

        render(panel(primary), dark: false, to: directory.appending(path: "panel-light@2x.png"))
        render(panel(primary), dark: true, to: directory.appending(path: "panel-dark@2x.png"))
        render(panel(everything), dark: false, to: directory.appending(path: "panel-light-full@2x.png"))
        // The icon comes from Icon Composer's exporter, which ignores the Mac's icon style setting:
        //   ictool PRMonitorApp/AppIcon.icon --export-image --output-file app-icon-1024.png \
        //     --platform macOS --rendition Default --width 1024 --height 1024 --scale 1
        exit(0)
    }

    /// Renders at exactly 2 px per point into a transparent bitmap, independent of the screen.
    @MainActor
    private static func render(_ view: some View, dark: Bool, to url: URL) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
        host.appearance = appearance
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = appearance
        window.contentView = host
        // The list measures its own height after the first layout pass, so settle, re-measure and
        // resize until the size stops changing before capturing.
        var size = host.frame.size
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: .now.addingTimeInterval(0.25))
            let fitted = host.fittingSize
            if fitted == size { break }
            size = fitted
            window.setContentSize(size)
            host.frame = NSRect(origin: .zero, size: size)
        }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// The panel's own surface, standing in for the system's glass (which can't render offscreen):
/// an opaque menu-like fill and the hairline rim macOS draws around menu bar panels. No shadow.
private struct PanelSurface: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.panelCornerRadius, style: .continuous)
        shape
            .fill(colorScheme == .dark ? Color(white: 0.16) : Color(white: 0.965))
            .overlay(shape.strokeBorder(.primary.opacity(colorScheme == .dark ? 0.16 : 0.1), lineWidth: 0.5))
    }
}

/// Portfolio fixture: two fictional repositories, three pull requests in three states.
private enum PortfolioData {
    static let now = Date.now

    static let pullRequests: [PullRequest] = [
        // Checkout: Vercel and Cursor Bugbot passed, Devin left review threads.
        pr("PF_1", "lumen-labs/checkout-web", 214, "Add Apple Pay to the checkout flow", author: "maya", minutesAgo: 4,
           checks: [
               check("Vercel", source: .commitStatus(creator: "vercel")),
               check("Cursor Bugbot", source: .checkRun(appName: "Cursor", appSlug: "cursor")),
               check("Devin Review", source: .checkRun(appName: "Devin", appSlug: "devin-ai-integration")),
           ],
           threads: [thread("devin-ai-integration"), thread("devin-ai-integration")]),
        // Checkout: still running.
        pr("PF_2", "lumen-labs/checkout-web", 209, "Retry failed payment webhooks with backoff", author: "sam", minutesAgo: 11,
           checks: [
               check("Vercel", source: .commitStatus(creator: "vercel")),
               check("build", source: .checkRun(appName: "GitHub Actions", appSlug: "github-actions")),
               check("test", source: .checkRun(appName: "GitHub Actions", appSlug: "github-actions"), outcome: .pending),
               check("Cursor Bugbot", source: .checkRun(appName: "Cursor", appSlug: "cursor"), outcome: .pending),
           ]),
        // Design system: everything green and approved.
        pr("PF_3", "lumen-labs/design-system", 88, "Adopt Liquid Glass tokens for buttons", author: "jordan", minutesAgo: 38,
           checks: [
               check("CI", source: .checkRun(appName: "GitHub Actions", appSlug: "github-actions")),
               check("Vercel", source: .commitStatus(creator: "vercel")),
               check("Cursor Bugbot", source: .checkRun(appName: "Cursor", appSlug: "cursor")),
           ],
           decision: .approved),
    ]

    private static func pr(
        _ id: String, _ repo: String, _ number: Int, _ title: String, author: String, minutesAgo: Double,
        checks: [CheckSignal], threads: [ThreadSignal] = [], decision: ReviewDecision? = nil
    ) -> PullRequest {
        PullRequest(
            id: id, repository: RepositoryID(parsing: repo)!, number: number, title: title,
            url: URL(string: "https://github.com/\(repo)/pull/\(number)")!, author: author, isDraft: false,
            createdAt: now.addingTimeInterval(-86_400), updatedAt: now.addingTimeInterval(-minutesAgo * 60),
            headSHA: "head-\(id)", headCommittedAt: now.addingTimeInterval(-(minutesAgo + 20) * 60), rollupState: nil,
            reviewDecision: decision, mergeable: .mergeable, checks: checks, requestedReviewers: [],
            reviews: [], threads: threads, comments: []
        )
    }

    private static func check(_ name: String, source: CheckSignal.Source, outcome: CheckSignal.Outcome = .succeeded) -> CheckSignal {
        CheckSignal(name: name, source: source, outcome: outcome, rawState: outcome == .pending ? "IN_PROGRESS" : "SUCCESS",
                    startedAt: now.addingTimeInterval(-600), completedAt: outcome == .pending ? nil : now.addingTimeInterval(-180), url: nil)
    }

    private static func thread(_ login: String) -> ThreadSignal {
        ThreadSignal(author: login, isBot: true, isResolved: false, isOutdated: false, createdAt: now.addingTimeInterval(-120))
    }
}
#endif
