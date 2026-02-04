import AppKit
import Combine
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var container: AppContainer?

    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var statusHostingView: NSHostingView<StatusBarLabel>?
    private var cancellables = Set<AnyCancellable>()

    private let preferredWidth: CGFloat = 520

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let container else { return }

        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        setupStatusItem()
        setupPopover(container: container)
        bindStatusUpdates(container: container)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            button.highlight(false)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))

        let hosting = NSHostingView(rootView: StatusBarLabel(status: .idle))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: button.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
        statusHostingView = hosting
    }

    private func setupPopover(container: AppContainer) {
        let rootView = ContentView(
            maxPopoverHeight: currentMaxPopoverHeight(),
            onSizeChange: { [weak self] size in
                self?.updatePopoverSize(size: size)
            }
        )
        .environmentObject(container.appState)
        .environmentObject(container.authStore)

        let controller = NSHostingController(rootView: rootView)
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: preferredWidth, height: 320)
    }

    private func bindStatusUpdates(container: AppContainer) {
        container.appState.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.updateStatusItem(container: container)
            }
            .store(in: &cancellables)

        container.authStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.updateStatusItem(container: container)
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem(container: AppContainer) {
        statusHostingView?.rootView = StatusBarLabel(status: container.appState.overallStatus)
        updatePopoverMaxHeight()
    }

    private func updatePopoverSize(size: CGSize) {
        let clampedHeight = min(currentMaxPopoverHeight(), max(260, size.height))
        if abs(popover.contentSize.height - clampedHeight) > 1 {
            popover.contentSize = NSSize(width: preferredWidth, height: clampedHeight)
        }
    }

    private func updatePopoverMaxHeight() {
        let clampedHeight = min(currentMaxPopoverHeight(), popover.contentSize.height)
        if abs(popover.contentSize.height - clampedHeight) > 1 {
            popover.contentSize = NSSize(width: preferredWidth, height: clampedHeight)
        }
    }

    private func currentMaxPopoverHeight() -> CGFloat {
        let screenHeight = statusItem?.button?.window?.screen?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height
            ?? 900
        return max(320, min(900, screenHeight - 120))
    }
}
