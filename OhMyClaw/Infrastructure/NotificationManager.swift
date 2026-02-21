import Foundation
import UserNotifications

/// Wrapper around UNUserNotificationCenter for posting macOS notifications.
/// Used for: config validation errors, disappeared files, processing errors.
final class NotificationManager: Sendable {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()

    init() {
        // Request notification permissions at initialization
        Task {
            try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    /// Post a notification to the user.
    /// - Parameters:
    ///   - title: Bold title text (e.g., "Oh My Claw")
    ///   - body: Detail message
    ///   - identifier: Unique ID for this notification (for dedup). Defaults to UUID.
    func notify(title: String, body: String, identifier: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier ?? UUID().uuidString,
            content: content,
            trigger: nil  // deliver immediately
        )

        center.add(request) { error in
            if let error = error {
                AppLogger.shared.error("Failed to post notification",
                                       context: ["error": error.localizedDescription])
            }
        }
    }

    /// Post a warning notification about config validation issues.
    func notifyConfigError(_ errors: [String]) {
        let body = errors.count == 1
            ? errors[0]
            : "\(errors.count) config issues found. Using defaults. Check log for details."
        notify(
            title: "Oh My Claw — Config Error",
            body: body,
            identifier: "config-validation-error"
        )
    }

    /// Notify the user that a file disappeared before it could be processed.
    func notifyFileDisappeared(filename: String) {
        notify(
            title: "Oh My Claw",
            body: "File '\(filename)' was removed before processing could complete.",
            identifier: "file-disappeared-\(filename)"
        )
    }
}
