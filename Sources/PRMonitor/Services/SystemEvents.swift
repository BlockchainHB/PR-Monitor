import AppKit
import Network
import ServiceManagement

/// Emits when the Mac wakes from sleep or the network comes back, so the monitor can refresh
/// immediately instead of waiting out its timer with stale data.
@MainActor
final class SystemEvents {
    private let pathMonitor = NWPathMonitor()
    private var observers: [NSObjectProtocol] = []
    private(set) var isOnline = true
    /// Low Data Mode or a metered connection (e.g. a phone hotspot): poll less often.
    private(set) var isConstrained = false

    func start(onResume: @escaping @MainActor () -> Void) {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { onResume() }
        })

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let constrained = path.isConstrained || path.isExpensive
            Task { @MainActor in
                guard let self else { return }
                self.isConstrained = constrained
                let cameBack = online && !self.isOnline
                self.isOnline = online
                if cameBack { onResume() }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "PRMonitor.network"))
    }
}

/// Launch at login via `SMAppService`, which shows up in System Settings › General › Login Items.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
