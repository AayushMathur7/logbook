import Foundation
import DriftlyCore
import UserNotifications

final class FocusGuardNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    private enum Constants {
        static let threadID = "driftly-focus-guard"
    }

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
                return try await center.requestAuthorization(options: [.alert, .sound])
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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
