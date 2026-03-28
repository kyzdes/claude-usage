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
}

struct UsageCaptureResult: Equatable, Sendable {
    let capturedAt: Date
    let screenText: String
    let rawScreenLines: [String]
    let sourceState: CaptureSourceState
}
