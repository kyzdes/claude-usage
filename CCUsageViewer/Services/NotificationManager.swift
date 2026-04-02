import AppKit
import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private var alertFired: [String: Bool] = [:]
    private var hasSeeded = false

    override init() {
        super.init()
        // Set delegate so notifications show even when app is in foreground
        UNUserNotificationCenter.current().delegate = self
    }

    // Show notification banner even when app is active
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func seedAlertFlags(
        snapshot: SubscriptionLimitSnapshot,
        warnThreshold: Int,
        dangerThreshold: Int
    ) {
        guard !hasSeeded else { return }
        hasSeeded = true

        let sessionPct = snapshot.currentSession?.progressPercent ?? 0
        let weeklyPct = snapshot.weeklyLimit?.progressPercent ?? 0
        let warn = Double(warnThreshold)
        let danger = Double(dangerThreshold)

        if sessionPct >= danger {
            alertFired["session_danger"] = true
            alertFired["session_warn"] = true
        } else if sessionPct >= warn {
            alertFired["session_warn"] = true
        }

        if weeklyPct >= danger {
            alertFired["weekly_danger"] = true
            alertFired["weekly_warn"] = true
        } else if weeklyPct >= warn {
            alertFired["weekly_warn"] = true
        }
    }

    func checkAndFireAlerts(
        snapshot: SubscriptionLimitSnapshot,
        warnThreshold: Int,
        dangerThreshold: Int,
        enabled: Bool
    ) async {
        guard enabled else { return }

        let sessionPct = snapshot.currentSession?.progressPercent ?? 0
        let weeklyPct = snapshot.weeklyLimit?.progressPercent ?? 0
        let warn = Double(warnThreshold)
        let danger = Double(dangerThreshold)

        // Reset flags when usage drops below warn
        if sessionPct < warn {
            alertFired["session_warn"] = false
            alertFired["session_danger"] = false
        }
        if weeklyPct < warn {
            alertFired["weekly_warn"] = false
            alertFired["weekly_danger"] = false
        }

        // Session alerts
        if sessionPct >= danger && alertFired["session_danger"] != true {
            alertFired["session_danger"] = true
            alertFired["session_warn"] = true
            await sendNotification(
                title: "CC Usage Viewer",
                body: "Current Session usage is at \(Int(sessionPct))% — running low"
            )
        } else if sessionPct >= warn && alertFired["session_warn"] != true {
            alertFired["session_warn"] = true
            await sendNotification(
                title: "CC Usage Viewer",
                body: "Current Session usage has reached \(Int(sessionPct))%"
            )
        }

        // Weekly alerts
        if weeklyPct >= danger && alertFired["weekly_danger"] != true {
            alertFired["weekly_danger"] = true
            alertFired["weekly_warn"] = true
            await sendNotification(
                title: "CC Usage Viewer",
                body: "Weekly Limit usage is at \(Int(weeklyPct))% — running low"
            )
        } else if weeklyPct >= warn && alertFired["weekly_warn"] != true {
            alertFired["weekly_warn"] = true
            await sendNotification(
                title: "CC Usage Viewer",
                body: "Weekly Limit usage has reached \(Int(weeklyPct))%"
            )
        }
    }

    func resetAlertFlags() {
        alertFired.removeAll()
        hasSeeded = false
    }

    func sendTestNotification() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            await requestPermission()
            let updated = await center.notificationSettings()
            if updated.authorizationStatus == .authorized {
                await sendNotification(
                    title: "CC Usage Viewer",
                    body: "Notifications enabled! You'll be alerted when usage crosses your thresholds.",
                    withDelay: true
                )
            } else {
                showBlockedAlert()
            }

        case .denied:
            showBlockedAlert()

        case .authorized, .provisional:
            await sendNotification(
                title: "CC Usage Viewer",
                body: "Notifications are working! You'll be alerted when usage crosses your thresholds.",
                withDelay: true
            )

        @unknown default:
            break
        }
    }

    private func showBlockedAlert() {
        let alert = NSAlert()
        alert.messageText = "Notifications Blocked"
        alert.informativeText = "Notifications are disabled for this app. Enable them in System Settings → Notifications → CC Usage Viewer."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open notification settings for this app
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func sendNotification(title: String, body: String, withDelay: Bool = false) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // Use a 1s delay trigger — nil trigger sometimes doesn't show banner on macOS
        let trigger: UNNotificationTrigger? = withDelay
            ? UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            : nil

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        try? await UNUserNotificationCenter.current().add(request)
    }
}
