import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private enum Keys {
        static let autoRefreshEnabled = "settings.autoRefreshEnabled"
        static let refreshIntervalMinutes = "settings.refreshIntervalMinutes"
        static let staleThresholdMinutes = "settings.staleThresholdMinutes"
        static let showRawCapture = "settings.showRawCapture"
    }

    private let defaults: UserDefaults

    var autoRefreshEnabled: Bool {
        didSet {
            defaults.set(autoRefreshEnabled, forKey: Keys.autoRefreshEnabled)
        }
    }

    var refreshIntervalMinutes: Int {
        didSet {
            defaults.set(max(1, refreshIntervalMinutes), forKey: Keys.refreshIntervalMinutes)
        }
    }

    var staleThresholdMinutes: Int {
        didSet {
            defaults.set(max(1, staleThresholdMinutes), forKey: Keys.staleThresholdMinutes)
        }
    }

    var showRawCapture: Bool {
        didSet {
            defaults.set(showRawCapture, forKey: Keys.showRawCapture)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.autoRefreshEnabled = defaults.object(forKey: Keys.autoRefreshEnabled) as? Bool ?? true
        self.refreshIntervalMinutes = defaults.object(forKey: Keys.refreshIntervalMinutes) as? Int ?? 5
        self.staleThresholdMinutes = defaults.object(forKey: Keys.staleThresholdMinutes) as? Int ?? 15
        self.showRawCapture = defaults.object(forKey: Keys.showRawCapture) as? Bool ?? false
    }

    var refreshSettingsKey: String {
        "\(autoRefreshEnabled)-\(refreshIntervalMinutes)-\(staleThresholdMinutes)-\(showRawCapture)"
    }

    var workingDirectoryDescription: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CCUsageViewer/ClaudeCLI", isDirectory: true)
            .path
    }
}
