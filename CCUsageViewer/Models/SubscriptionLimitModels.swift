import Foundation

// MARK: - Data Source

enum DataSourceKind: String, Sendable {
    case ptyCapture
    case claudeAPI
}

enum CaptureSourceState: String, Sendable {
    case live
    case partial
    case stale
    case unavailable
    case authRequired
    case apiKeyMode
}

struct LimitSection: Equatable, Sendable {
    let title: String
    let usedText: String?
    let remainingText: String?
    let progressPercent: Double?
    let resetText: String?
    let resetsAt: Date?
    let windowDurationMinutes: Int?

    var primaryMetricText: String? {
        remainingText ?? usedText
    }

    init(
        title: String,
        usedText: String? = nil,
        remainingText: String? = nil,
        progressPercent: Double? = nil,
        resetText: String? = nil,
        resetsAt: Date? = nil,
        windowDurationMinutes: Int? = nil
    ) {
        self.title = title
        self.usedText = usedText
        self.remainingText = remainingText
        self.progressPercent = progressPercent
        self.resetText = resetText
        self.resetsAt = resetsAt
        self.windowDurationMinutes = windowDurationMinutes
    }
}

// MARK: - Per-Model Breakdown

struct ModelLimitSection: Equatable, Sendable, Identifiable {
    let id: String
    let modelName: String
    let utilization: Double
    let resetsAt: Date?
}

// MARK: - Extra Usage / Overage

struct ExtraUsageInfo: Equatable, Sendable {
    let isEnabled: Bool
    let utilization: Double?
    let usedCents: Int?
    let limitCents: Int?
    let balanceCents: Int?
    let currency: String
}

struct SubscriptionLimitSnapshot: Equatable, Sendable {
    let capturedAt: Date
    let planName: String
    let accountLabel: String?
    let currentSession: LimitSection?
    let weeklyLimit: LimitSection?
    let rawText: String
    let isPartial: Bool
    let perModelLimits: [ModelLimitSection]
    let extraUsage: ExtraUsageInfo?
    let dataSource: DataSourceKind

    init(
        capturedAt: Date,
        planName: String,
        accountLabel: String? = nil,
        currentSession: LimitSection? = nil,
        weeklyLimit: LimitSection? = nil,
        rawText: String,
        isPartial: Bool,
        perModelLimits: [ModelLimitSection] = [],
        extraUsage: ExtraUsageInfo? = nil,
        dataSource: DataSourceKind = .ptyCapture
    ) {
        self.capturedAt = capturedAt
        self.planName = planName
        self.accountLabel = accountLabel
        self.currentSession = currentSession
        self.weeklyLimit = weeklyLimit
        self.rawText = rawText
        self.isPartial = isPartial
        self.perModelLimits = perModelLimits
        self.extraUsage = extraUsage
        self.dataSource = dataSource
    }

    func applyingPlanHint(_ observedPlanName: String?) -> SubscriptionLimitSnapshot {
        guard planName == "Unknown Plan",
              let observedPlanName,
              !observedPlanName.isEmpty else {
            return self
        }

        return SubscriptionLimitSnapshot(
            capturedAt: capturedAt,
            planName: observedPlanName,
            accountLabel: accountLabel,
            currentSession: currentSession,
            weeklyLimit: weeklyLimit,
            rawText: rawText,
            isPartial: isPartial,
            perModelLimits: perModelLimits,
            extraUsage: extraUsage,
            dataSource: dataSource
        )
    }
}

struct UsageCaptureResult: Equatable, Sendable {
    let capturedAt: Date
    let screenText: String
    let rawScreenLines: [String]
    let sourceState: CaptureSourceState
    let observedPlanName: String?
}

