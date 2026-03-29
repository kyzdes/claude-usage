import Foundation

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

    var primaryMetricText: String? {
        remainingText ?? usedText
    }
}

struct SubscriptionLimitSnapshot: Equatable, Sendable {
    let capturedAt: Date
    let planName: String
    let currentSession: LimitSection?
    let weeklyLimit: LimitSection?
    let rawText: String
    let isPartial: Bool

    func applyingPlanHint(_ observedPlanName: String?) -> SubscriptionLimitSnapshot {
        guard planName == "Unknown Plan",
              let observedPlanName,
              !observedPlanName.isEmpty else {
            return self
        }

        return SubscriptionLimitSnapshot(
            capturedAt: capturedAt,
            planName: observedPlanName,
            currentSession: currentSession,
            weeklyLimit: weeklyLimit,
            rawText: rawText,
            isPartial: isPartial
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
