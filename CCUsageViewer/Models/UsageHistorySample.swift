import Foundation
import SwiftData

@Model
final class UsageHistorySample {
    var timestamp: Date
    var sessionPercent: Double
    var weeklyPercent: Double
    var sonnetPercent: Double?
    var opusPercent: Double?
    var coworkPercent: Double?
    var oauthAppsPercent: Double?
    var extraUsagePercent: Double?

    init(
        timestamp: Date,
        sessionPercent: Double,
        weeklyPercent: Double,
        sonnetPercent: Double? = nil,
        opusPercent: Double? = nil,
        coworkPercent: Double? = nil,
        oauthAppsPercent: Double? = nil,
        extraUsagePercent: Double? = nil
    ) {
        self.timestamp = timestamp
        self.sessionPercent = sessionPercent
        self.weeklyPercent = weeklyPercent
        self.sonnetPercent = sonnetPercent
        self.opusPercent = opusPercent
        self.coworkPercent = coworkPercent
        self.oauthAppsPercent = oauthAppsPercent
        self.extraUsagePercent = extraUsagePercent
    }
}
