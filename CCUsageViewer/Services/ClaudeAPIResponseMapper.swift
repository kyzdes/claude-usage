import Foundation

struct ClaudeAPIResponseMapper: Sendable {
    nonisolated(unsafe) private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let iso8601FormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    func map(
        usage: ClaudeAPIUsageResponse,
        overage: ClaudeAPIOverageResponse?,
        prepaid: ClaudeAPIPrepaidResponse?
    ) -> SubscriptionLimitSnapshot {
        let currentSession = mapLimitSection(
            title: "Current session",
            metric: usage.fiveHour,
            windowDurationMinutes: 300
        )

        let weeklyLimit = mapLimitSection(
            title: "Weekly limit",
            metric: usage.sevenDay,
            windowDurationMinutes: 10080
        )

        let perModelLimits = buildPerModelLimits(from: usage)
        let extraUsage = buildExtraUsage(overage: overage, prepaid: prepaid)

        let isPartial = currentSession == nil && weeklyLimit == nil

        return SubscriptionLimitSnapshot(
            capturedAt: Date(),
            planName: "Claude",
            currentSession: currentSession,
            weeklyLimit: weeklyLimit,
            rawText: "",
            isPartial: isPartial,
            perModelLimits: perModelLimits,
            extraUsage: extraUsage,
            dataSource: .claudeAPI
        )
    }

    private func mapLimitSection(
        title: String,
        metric: ClaudeAPIUsageResponse.UsageMetric?,
        windowDurationMinutes: Int
    ) -> LimitSection? {
        guard let metric else { return nil }

        let pct = min(max(metric.utilization, 0), 100)
        let remaining = 100 - pct
        let resetsAt = parseDate(metric.resetsAt)

        let resetText: String? = if let resetsAt {
            formatResetText(resetsAt)
        } else {
            nil
        }

        return LimitSection(
            title: title,
            usedText: "\(Int(pct))% used",
            remainingText: "\(Int(remaining))% remaining",
            progressPercent: pct,
            resetText: resetText,
            resetsAt: resetsAt,
            windowDurationMinutes: windowDurationMinutes
        )
    }

    private func buildPerModelLimits(from usage: ClaudeAPIUsageResponse) -> [ModelLimitSection] {
        var models: [ModelLimitSection] = []

        if let sonnet = usage.sevenDaySonnet {
            models.append(ModelLimitSection(
                id: "seven_day_sonnet",
                modelName: "Sonnet (7d)",
                utilization: sonnet.utilization,
                resetsAt: parseDate(sonnet.resetsAt)
            ))
        }

        if let opus = usage.sevenDayOpus {
            models.append(ModelLimitSection(
                id: "seven_day_opus",
                modelName: "Opus (7d)",
                utilization: opus.utilization,
                resetsAt: parseDate(opus.resetsAt)
            ))
        }

        if let cowork = usage.sevenDayCowork {
            models.append(ModelLimitSection(
                id: "seven_day_cowork",
                modelName: "Cowork (7d)",
                utilization: cowork.utilization,
                resetsAt: parseDate(cowork.resetsAt)
            ))
        }

        if let oauth = usage.sevenDayOauthApps {
            models.append(ModelLimitSection(
                id: "seven_day_oauth_apps",
                modelName: "OAuth Apps (7d)",
                utilization: oauth.utilization,
                resetsAt: parseDate(oauth.resetsAt)
            ))
        }

        return models
    }

    private func buildExtraUsage(
        overage: ClaudeAPIOverageResponse?,
        prepaid: ClaudeAPIPrepaidResponse?
    ) -> ExtraUsageInfo? {
        guard let overage else {
            guard let prepaid, let amount = prepaid.amount else { return nil }
            return ExtraUsageInfo(
                isEnabled: false,
                utilization: nil,
                usedCents: nil,
                limitCents: nil,
                balanceCents: amount,
                currency: prepaid.currency ?? "USD"
            )
        }

        let isEnabled = overage.isEnabled ?? (overage.effectiveLimit != nil)
        let limit = overage.effectiveLimit
        let used = overage.effectiveUsed

        let utilization: Double? = if let limit, limit > 0, let used {
            (Double(used) / Double(limit)) * 100
        } else {
            nil
        }

        var balanceCents: Int? = nil
        if let prepaid, let amount = prepaid.amount {
            balanceCents = amount
        }

        return ExtraUsageInfo(
            isEnabled: isEnabled,
            utilization: utilization,
            usedCents: used,
            limitCents: limit,
            balanceCents: balanceCents,
            currency: overage.currency ?? prepaid?.currency ?? "USD"
        )
    }

    private func parseDate(_ isoString: String?) -> Date? {
        guard let isoString else { return nil }
        return Self.iso8601Formatter.date(from: isoString)
            ?? Self.iso8601FormatterNoFraction.date(from: isoString)
    }

    private func formatResetText(_ date: Date) -> String {
        let diff = date.timeIntervalSinceNow
        guard diff > 0 else { return "Resetting..." }

        let hours = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60

        if hours >= 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return "Resets in \(days)d \(remainingHours)h"
        } else if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        } else {
            return "Resets in \(minutes)m"
        }
    }
}
