import Foundation
import DriftlyCore
import UserNotifications

final class FocusGuardNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    enum Action: String {
        case backOnTrack = "FOCUS_GUARD_BACK_ON_TRACK"
        case snooze = "FOCUS_GUARD_SNOOZE"
        case ignore = "FOCUS_GUARD_IGNORE"
    }

    private enum Constants {
        static let categoryID = "DRIFTLY_FOCUS_GUARD"
        static let threadID = "driftly-focus-guard"
    }

    var onAction: ((Action, String?) -> Void)?

    private let center: UNUserNotificationCenter? = {
        guard Bundle.main.bundleURL.pathExtension == "app",
              let bundleID = Bundle.main.bundleIdentifier,
              !bundleID.isEmpty else {
            return nil
        }
        return UNUserNotificationCenter.current()
    }()

    override init() {
        super.init()
        center?.delegate = self
        registerCategories()
    }

    static var notificationsSupported: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
            && !(Bundle.main.bundleIdentifier?.isEmpty ?? true)
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        guard let center else { return false }

        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                registerCategories()
                return granted
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    func authorizationGranted() async -> Bool {
        guard let center else { return false }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    func schedule(prompt: FocusGuardPrompt) async {
        guard let center else {
            scheduleFallback(prompt: prompt)
            return
        }

        guard await authorizationGranted() else {
            scheduleFallback(prompt: prompt)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = prompt.reason
        content.subtitle = ""
        content.body = prompt.message
        content.sound = .default
        content.categoryIdentifier = Constants.categoryID
        content.threadIdentifier = Constants.threadID
        content.userInfo = [
            "session_id": prompt.sessionID,
            "prompt_id": prompt.id,
        ]

        let request = UNNotificationRequest(
            identifier: "focus-guard-\(prompt.id)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )

        do {
            try await center.add(request)
        } catch {
            scheduleFallback(prompt: prompt)
        }
    }

    private func registerCategories() {
        guard let center else { return }

        let backOnTrack = UNNotificationAction(
            identifier: Action.backOnTrack.rawValue,
            title: "Back on track"
        )
        let snooze = UNNotificationAction(
            identifier: Action.snooze.rawValue,
            title: "Snooze"
        )
        let ignore = UNNotificationAction(
            identifier: Action.ignore.rawValue,
            title: "Ignore"
        )

        let category = UNNotificationCategory(
            identifier: Constants.categoryID,
            actions: [backOnTrack, snooze, ignore],
            intentIdentifiers: []
        )

        center.setNotificationCategories([category])
    }

    private func scheduleFallback(prompt: FocusGuardPrompt) {
        let body = appleScriptString(prompt.message)
        let title = appleScriptString(prompt.reason)
        let script = """
        display notification \(body) with title \(title)
        """
        _ = AppleScriptRunner.run(script, timeout: 1.2)
    }

    private func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func action(from identifier: String) -> Action? {
        Action(rawValue: identifier)
    }

    private func sessionID(from response: UNNotificationResponse) -> String? {
        response.notification.request.content.userInfo["session_id"] as? String
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.content.categoryIdentifier == Constants.categoryID,
              let action = action(from: response.actionIdentifier) else {
            return
        }

        let sessionID = sessionID(from: response)
        await MainActor.run {
            onAction?(action, sessionID)
        }
    }
}
