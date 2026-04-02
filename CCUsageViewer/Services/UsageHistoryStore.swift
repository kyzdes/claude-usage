import Foundation
import SwiftData

@MainActor
final class UsageHistoryStore {
    let modelContainer: ModelContainer

    init() throws {
        let schema = Schema([UsageHistorySample.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        self.modelContainer = try ModelContainer(for: schema, configurations: [config])
    }

    @discardableResult
    func recordSample(from snapshot: SubscriptionLimitSnapshot) -> UsageHistorySample {
        let context = modelContainer.mainContext

        let sessionPct = snapshot.currentSession?.progressPercent ?? 0
        let weeklyPct = snapshot.weeklyLimit?.progressPercent ?? 0

        let sonnet = snapshot.perModelLimits.first(where: { $0.id == "seven_day_sonnet" })?.utilization
        let opus = snapshot.perModelLimits.first(where: { $0.id == "seven_day_opus" })?.utilization
        let cowork = snapshot.perModelLimits.first(where: { $0.id == "seven_day_cowork" })?.utilization
        let oauth = snapshot.perModelLimits.first(where: { $0.id == "seven_day_oauth_apps" })?.utilization
        let extra = snapshot.extraUsage?.utilization

        let sample = UsageHistorySample(
            timestamp: snapshot.capturedAt,
            sessionPercent: sessionPct,
            weeklyPercent: weeklyPct,
            sonnetPercent: sonnet,
            opusPercent: opus,
            coworkPercent: cowork,
            oauthAppsPercent: oauth,
            extraUsagePercent: extra
        )

        context.insert(sample)
        try? context.save()
        return sample
    }

    func samples(from startDate: Date, to endDate: Date = Date()) -> [UsageHistorySample] {
        let context = modelContainer.mainContext
        let predicate = #Predicate<UsageHistorySample> { sample in
            sample.timestamp >= startDate && sample.timestamp <= endDate
        }
        let descriptor = FetchDescriptor<UsageHistorySample>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp)]
        )

        return (try? context.fetch(descriptor)) ?? []
    }

    func allSamples() -> [UsageHistorySample] {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<UsageHistorySample>(
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func sampleCount() -> Int {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<UsageHistorySample>()
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    func deleteAllSamples() {
        let context = modelContainer.mainContext
        do {
            try context.delete(model: UsageHistorySample.self)
            try context.save()
        } catch {
            // Silently fail — UI can retry
        }
    }
}
