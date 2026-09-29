import AppKit
@preconcurrency import UserNotifications

/// Posts notifications and opens the pull request when one is clicked.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    nonisolated private static let urlKey = "url"
    private static let categoryID = "pull-request"
    private static let openActionID = "open"

    /// Notification Center only works inside an app bundle (not `swift run`, previews, or tests).
    static var isAvailable: Bool {
        let environment = ProcessInfo.processInfo.environment
        guard environment["XCODE_RUNNING_FOR_PREVIEWS"] == nil, environment["XCTestConfigurationFilePath"] == nil else {
            return false
        }
        return Bundle.main.bundleURL.pathExtension == "app"
    }

    private var center: UNUserNotificationCenter? {
        Self.isAvailable ? .current() : nil
    }

    func activate() {
        guard let center else { return }
        center.delegate = self
        let open = UNNotificationAction(identifier: Self.openActionID, title: "Open Pull Request", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryID, actions: [open], intentIdentifiers: []),
        ])
    }

    /// Asks for permission in context: the first time there is something worth notifying about,
    /// rather than on first launch.
    func requestAuthorizationIfNeeded() async {
        guard let center else { return }
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus? {
        await center?.notificationSettings().authorizationStatus
    }

    func post(_ notifications: [PlannedNotification]) async {
        guard let center, !notifications.isEmpty else { return }
        await requestAuthorizationIfNeeded()
        for planned in notifications {
            let content = UNMutableNotificationContent()
            content.title = planned.title
            content.subtitle = planned.subtitle
            content.body = planned.body
            content.sound = .default
            content.threadIdentifier = planned.key.description
            content.categoryIdentifier = Self.categoryID
            content.userInfo = [Self.urlKey: planned.url.absoluteString]
            try? await center.add(UNNotificationRequest(identifier: planned.identifier, content: content, trigger: nil))
        }
    }

    func postTest() async -> Bool {
        guard let center else { return false }
        await requestAuthorizationIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = "PR Monitor"
        content.subtitle = "Notifications are working"
        content.body = "You'll hear from PR Monitor when your pull requests are ready for review."
        content.sound = .default
        do {
            try await center.add(UNNotificationRequest(identifier: "test", content: content, trigger: nil))
            return true
        } catch {
            return false
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier != UNNotificationDismissActionIdentifier,
              let string = response.notification.request.content.userInfo[Self.urlKey] as? String,
              let url = URL(string: string) else { return }
        await MainActor.run { _ = NSWorkspace.shared.open(url) }
    }
}
