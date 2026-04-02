import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    let historyStore: UsageHistoryStore
    var timeRange: DashboardTimeRange = .sevenDays
    var samples: [UsageHistorySample] = []
    var sampleCount: Int = 0

    init(historyStore: UsageHistoryStore) {
        self.historyStore = historyStore
    }

    func loadSamples() {
        if let offset = timeRange.dateOffset {
            let startDate = Date().addingTimeInterval(-offset)
            samples = historyStore.samples(from: startDate)
        } else {
            samples = historyStore.allSamples()
        }
        sampleCount = historyStore.sampleCount()
    }

    func deleteAllHistory() {
        historyStore.deleteAllSamples()
        samples = []
        sampleCount = 0
    }
}
