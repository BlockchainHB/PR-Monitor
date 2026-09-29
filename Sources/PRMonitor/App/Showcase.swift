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
