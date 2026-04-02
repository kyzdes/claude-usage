import Foundation
import Observation

@MainActor
@Observable
final class LimitViewModel {
    enum ViewState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private let appModel: AppModel
    private let claudeCaptureService: any ClaudeUsageCaptureServiceProtocol
    private let claudeParser: any UsageScreenParserProtocol
    private let sessionKeyStorage: SessionKeyStorageProtocol
    private let apiService: ClaudeAPIServiceProtocol
    private let responseMapper: ClaudeAPIResponseMapper

    var historyStore: UsageHistoryStore?
    let notificationManager: NotificationManager

    private var refreshTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var hasStarted = false
    private var isFirstLoad = true

    // Timer state
    var sessionResetsAt: Date?
    var weeklyResetsAt: Date?
    var countdownTick: Date = Date()

    var claudeState: ViewState = .idle
    var claudeSourceState: CaptureSourceState = .unavailable
    var claudeSnapshot: SubscriptionLimitSnapshot?
    var claudeLastGoodSnapshot: SubscriptionLimitSnapshot?
    var claudeLastErrorMessage: String?
    var claudeLastHint: String?
    var claudeDiagnosticsText = ""
    var claudeLastAttemptAt: Date?

    init(
        appModel: AppModel,
        claudeCaptureService: any ClaudeUsageCaptureServiceProtocol = ClaudeUsageCaptureService(),
        claudeParser: any UsageScreenParserProtocol = UsageScreenParser(),
        sessionKeyStorage: SessionKeyStorageProtocol = SessionKeyStorage(),
        apiService: ClaudeAPIServiceProtocol = ClaudeAPIService(),
        responseMapper: ClaudeAPIResponseMapper = ClaudeAPIResponseMapper(),
        notificationManager: NotificationManager = NotificationManager()
    ) {
        self.appModel = appModel
        self.claudeCaptureService = claudeCaptureService
        self.claudeParser = claudeParser
        self.sessionKeyStorage = sessionKeyStorage
        self.apiService = apiService
        self.responseMapper = responseMapper
        self.notificationManager = notificationManager
    }

    func startIfNeeded() {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        reconfigureAutoRefresh()
        startCountdownTimer()
        Task { await notificationManager.requestPermission() }
    }

    func reconfigureAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.refresh(forceVisibleLoading: self.claudeSnapshot == nil)
            while !Task.isCancelled {
                let seconds = UInt64(max(1, self.appModel.refreshIntervalMinutes) * 60)
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                guard !Task.isCancelled else {
                    return
                }

                if self.appModel.autoRefreshEnabled {
                    await self.refresh(forceVisibleLoading: false)
                }
            }
        }
    }

    var isRefreshing: Bool {
        claudeState == .loading
    }

    var isSnapshotStale: Bool {
        let referenceDate = claudeSnapshot?.capturedAt ?? claudeLastGoodSnapshot?.capturedAt
        guard let referenceDate else {
            return true
        }
        return Date().timeIntervalSince(referenceDate) > Double(appModel.staleThresholdMinutes * 60)
    }

    var primarySnapshot: SubscriptionLimitSnapshot? {
        claudeSnapshot
    }

    var menuBarTitle: String {
        if appModel.compactMenuBarMode {
            return compactMenuBarTitle
        }

        if isRefreshing, claudeSnapshot == nil {
            return "Claude\u{2026}"
        }

        if let planName = claudeSnapshot?.displayPlanName,
           let metric = claudeSnapshot?.currentSession?.primaryMetricText {
            let shortPlan = planName.replacingOccurrences(of: "Claude ", with: "")
            return "\(shortPlan) \(metric)"
        }

        if let planName = claudeSnapshot?.displayPlanName {
            return planName.replacingOccurrences(of: "Claude ", with: "")
        }

        if let metric = claudeSnapshot?.currentSession?.primaryMetricText {
            return metric
        }

        return "Claude"
    }

    var compactMenuBarTitle: String {
        // Depend on countdownTick to trigger SwiftUI updates every second
        _ = countdownTick
        guard let session = claudeSnapshot?.currentSession else { return "CC" }
        let pct = Int(session.progressPercent ?? 0)
        let countdown = formatCountdown(sessionResetsAt)
        if countdown.isEmpty {
            return "\(pct)%"
        }
        return "\(pct)% \u{00B7} \(countdown)"
    }

    var menuBarSymbol: String {
        switch claudeSourceState {
        case .live:
            return "gauge.open.with.lines.needle.33percent"
        case .partial, .stale:
            return "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        case .apiKeyMode, .authRequired, .unavailable:
            return "exclamationmark.triangle"
        }
    }

    func refresh(forceVisibleLoading: Bool = true) async {
        if forceVisibleLoading || claudeSnapshot == nil {
            claudeState = .loading
        }
        claudeLastAttemptAt = .now
        claudeLastErrorMessage = nil
        claudeLastHint = nil

        do {
            let snapshot: SubscriptionLimitSnapshot

            // Try coordinator (API with PTY fallback) based on preference
            if appModel.preferredDataSource != .ptyCapture,
               sessionKeyStorage.getSessionKey() != nil,
               sessionKeyStorage.getOrganizationId() != nil {
                let coordinator = UsageDataSourceCoordinator(
                    preference: appModel.preferredDataSource,
                    sessionKeyStorage: sessionKeyStorage,
                    apiService: apiService,
                    responseMapper: responseMapper,
                    claudeCaptureService: claudeCaptureService,
                    claudeParser: claudeParser
                )
                snapshot = try await coordinator.fetchSnapshot()
                claudeDiagnosticsText = "Source: \(snapshot.dataSource.rawValue)"
            } else {
                // PTY-only path (original)
                let capture = try await claudeCaptureService.captureUsage()
                claudeDiagnosticsText = capture.screenText
                snapshot = try claudeParser.parse(
                    screenText: capture.screenText,
                    capturedAt: capture.capturedAt
                )
                .applyingPlanHint(capture.observedPlanName)
            }

            claudeSnapshot = snapshot
            claudeLastGoodSnapshot = snapshot
            claudeSourceState = snapshot.isPartial ? .partial : .live
            claudeState = .loaded

            // Update timer state
            sessionResetsAt = snapshot.currentSession?.resetsAt
            weeklyResetsAt = snapshot.weeklyLimit?.resetsAt

            // Record history
            historyStore?.recordSample(from: snapshot)

            // Fire notifications
            if isFirstLoad {
                isFirstLoad = false
                notificationManager.seedAlertFlags(
                    snapshot: snapshot,
                    warnThreshold: appModel.warnThreshold,
                    dangerThreshold: appModel.dangerThreshold
                )
            } else {
                await notificationManager.checkAndFireAlerts(
                    snapshot: snapshot,
                    warnThreshold: appModel.warnThreshold,
                    dangerThreshold: appModel.dangerThreshold,
                    enabled: appModel.notificationsEnabled
                )
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            claudeLastErrorMessage = message
            claudeLastHint = "Check Claude CLI availability/login, then refresh."
            claudeDiagnosticsText = claudeDiagnosticsText.isEmpty ? message : claudeDiagnosticsText

            if let claudeLastGoodSnapshot {
                claudeSnapshot = claudeLastGoodSnapshot
                claudeSourceState = isSnapshotStale ? .stale : .partial
            } else {
                claudeSourceState = mapClaudeSourceState(for: error)
            }

            claudeState = .failed(message)
        }
    }

    private func mapClaudeSourceState(for error: Error) -> CaptureSourceState {
        if let captureError = error as? ClaudeUsageCaptureError {
            switch captureError {
            case .claudeNotInstalled:
                return .unavailable
            case .emptyCapture:
                return .authRequired
            case .screenNotRecognized(_):
                return .partial
            case .spawnFailed, .timeout(_, _):
                return .unavailable
            }
        }

        if error is UsageScreenParserError {
            return .partial
        }

        return .unavailable
    }

    private func startCountdownTimer() {
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self else { return }

                self.countdownTick = Date()

                // Auto-refresh when session timer hits 0
                if let resetsAt = self.sessionResetsAt, resetsAt.timeIntervalSinceNow <= 0 {
                    self.sessionResetsAt = nil
                    try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s delay for server sync
                    guard !Task.isCancelled else { return }
                    await self.refresh(forceVisibleLoading: false)
                }
            }
        }
    }

    func formatCountdown(_ date: Date?) -> String {
        guard let date else { return "" }
        let diff = date.timeIntervalSinceNow
        guard diff > 0 else { return "Resetting..." }

        let totalSeconds = Int(diff)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours >= 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return "\(days)d \(remainingHours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            let seconds = totalSeconds % 60
            return "\(minutes)m \(seconds)s"
        }
    }
}

extension SubscriptionLimitSnapshot {
    var displayPlanName: String? {
        planName == "Unknown Plan" ? nil : planName
    }
}
