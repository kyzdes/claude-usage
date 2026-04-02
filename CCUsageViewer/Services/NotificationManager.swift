import Foundation
import UserNotifications

@MainActor
final class NotificationManager {
    private var alertFired: [String: Bool] = [:]
    private var hasSeeded = false

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
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

    private func sendNotification(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }
}
