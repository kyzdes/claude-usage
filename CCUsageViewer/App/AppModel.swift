import Foundation
import Observation

enum DataSourcePreference: String, CaseIterable, Sendable {
    case api
    case autoFallback
    case ptyCapture

    var title: String {
        switch self {
        case .api:
            return "API only (Recommended)"
        case .autoFallback:
            return "API + PTY fallback"
        case .ptyCapture:
            return "PTY only (Not recommended)"
        }
    }

    var needsRiskAcceptance: Bool {
        self == .autoFallback || self == .ptyCapture
    }
}

enum DashboardTimeRange: String, CaseIterable, Sendable {
    case sevenDays
    case thirtyDays
    case ninetyDays
    case all

    var title: String {
        switch self {
        case .sevenDays: return "7 days"
        case .thirtyDays: return "30 days"
        case .ninetyDays: return "90 days"
        case .all: return "All time"
        }
    }

    var dateOffset: TimeInterval? {
        switch self {
        case .sevenDays: return 7 * 24 * 3600
        case .thirtyDays: return 30 * 24 * 3600
        case .ninetyDays: return 90 * 24 * 3600
        case .all: return nil
        }
    }
}

@MainActor
@Observable
final class AppModel {
    private enum Keys {
        static let autoRefreshEnabled = "settings.autoRefreshEnabled"
        static let refreshIntervalMinutes = "settings.refreshIntervalMinutes"
        static let staleThresholdMinutes = "settings.staleThresholdMinutes"
        static let showRawCapture = "settings.showRawCapture"
        static let preferredDataSource = "settings.preferredDataSource"
        static let notificationsEnabled = "settings.notificationsEnabled"
        static let ptyRiskAcceptedAt = "settings.ptyRiskAcceptedAt"
        static let warnThreshold = "settings.warnThreshold"
        static let dangerThreshold = "settings.dangerThreshold"
        static let compactMenuBarMode = "settings.compactMenuBarMode"
        static let dashboardTimeRange = "settings.dashboardTimeRange"
    }

    private let defaults: UserDefaults

    var autoRefreshEnabled: Bool {
        didSet { defaults.set(autoRefreshEnabled, forKey: Keys.autoRefreshEnabled) }
    }

    var refreshIntervalMinutes: Int {
        didSet { defaults.set(max(1, refreshIntervalMinutes), forKey: Keys.refreshIntervalMinutes) }
    }

    var staleThresholdMinutes: Int {
        didSet { defaults.set(max(1, staleThresholdMinutes), forKey: Keys.staleThresholdMinutes) }
    }

    var showRawCapture: Bool {
        didSet { defaults.set(showRawCapture, forKey: Keys.showRawCapture) }
    }

    var preferredDataSource: DataSourcePreference {
        didSet { defaults.set(preferredDataSource.rawValue, forKey: Keys.preferredDataSource) }
    }

    var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }

    var warnThreshold: Int {
        didSet { defaults.set(max(1, min(99, warnThreshold)), forKey: Keys.warnThreshold) }
    }

    var dangerThreshold: Int {
        didSet { defaults.set(max(1, min(99, dangerThreshold)), forKey: Keys.dangerThreshold) }
    }

    var compactMenuBarMode: Bool {
        didSet { defaults.set(compactMenuBarMode, forKey: Keys.compactMenuBarMode) }
    }

    var dashboardTimeRange: DashboardTimeRange {
        didSet { defaults.set(dashboardTimeRange.rawValue, forKey: Keys.dashboardTimeRange) }
    }

    func logPtyRiskAcceptance() {
        defaults.set(Date().timeIntervalSince1970, forKey: Keys.ptyRiskAcceptedAt)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.autoRefreshEnabled = defaults.object(forKey: Keys.autoRefreshEnabled) as? Bool ?? true
        self.refreshIntervalMinutes = defaults.object(forKey: Keys.refreshIntervalMinutes) as? Int ?? 5
        self.staleThresholdMinutes = defaults.object(forKey: Keys.staleThresholdMinutes) as? Int ?? 15
        self.showRawCapture = defaults.object(forKey: Keys.showRawCapture) as? Bool ?? false
        self.notificationsEnabled = defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true
        self.warnThreshold = defaults.object(forKey: Keys.warnThreshold) as? Int ?? 75
        self.dangerThreshold = defaults.object(forKey: Keys.dangerThreshold) as? Int ?? 90
        self.compactMenuBarMode = defaults.object(forKey: Keys.compactMenuBarMode) as? Bool ?? false

        if let savedSource = defaults.string(forKey: Keys.preferredDataSource),
           let source = DataSourcePreference(rawValue: savedSource) {
            self.preferredDataSource = source
        } else {
            self.preferredDataSource = .api
        }

        if let savedRange = defaults.string(forKey: Keys.dashboardTimeRange),
           let range = DashboardTimeRange(rawValue: savedRange) {
            self.dashboardTimeRange = range
        } else {
            self.dashboardTimeRange = .sevenDays
        }
    }

    var refreshSettingsKey: String {
        "\(autoRefreshEnabled)-\(refreshIntervalMinutes)-\(staleThresholdMinutes)-\(showRawCapture)"
    }

    var claudeWorkingDirectoryDescription: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CCUsageViewer/ClaudeCLI", isDirectory: true)
            .path
    }
}
