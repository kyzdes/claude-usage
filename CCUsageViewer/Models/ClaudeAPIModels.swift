import Foundation

// MARK: - Usage Endpoint

struct ClaudeAPIUsageResponse: Codable, Sendable {
    let fiveHour: UsageMetric?
    let sevenDay: UsageMetric?
    let sevenDaySonnet: UsageMetric?
    let sevenDayOpus: UsageMetric?
    let sevenDayCowork: UsageMetric?
    let sevenDayOauthApps: UsageMetric?

    struct UsageMetric: Codable, Sendable {
        let utilization: Double
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOpus = "seven_day_opus"
        case sevenDayCowork = "seven_day_cowork"
        case sevenDayOauthApps = "seven_day_oauth_apps"
    }
}

// MARK: - Organizations Endpoint

struct ClaudeAPIOrganization: Codable, Sendable {
    let uuid: String?
    let id: String?
    let name: String?

    var organizationId: String? {
        uuid ?? id
    }
}

// MARK: - Overage Endpoint

struct ClaudeAPIOverageResponse: Codable, Sendable {
    let monthlyCreditLimit: Int?
    let spendLimitAmountCents: Int?
    let usedCredits: Int?
    let balanceCents: Int?
    let isEnabled: Bool?
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case monthlyCreditLimit = "monthly_credit_limit"
        case spendLimitAmountCents = "spend_limit_amount_cents"
        case usedCredits = "used_credits"
        case balanceCents = "balance_cents"
        case isEnabled = "is_enabled"
        case currency
    }

    var effectiveLimit: Int? {
        monthlyCreditLimit ?? spendLimitAmountCents
    }

    var effectiveUsed: Int? {
        usedCredits ?? balanceCents
    }
}

// MARK: - Prepaid Endpoint

struct ClaudeAPIPrepaidResponse: Codable, Sendable {
    let amount: Int?
    let currency: String?
}
