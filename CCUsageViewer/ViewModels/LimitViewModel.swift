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
    private let captureService: ClaudeUsageCaptureService
    private let parser: UsageScreenParser

    private var refreshTask: Task<Void, Never>?
    private var hasStarted = false

    var state: ViewState = .idle
    var sourceState: CaptureSourceState = .unavailable
    var snapshot: SubscriptionLimitSnapshot?
    var lastGoodSnapshot: SubscriptionLimitSnapshot?
    var lastErrorMessage: String?
    var diagnosticsText = ""
    var lastAttemptAt: Date?

    init(
        appModel: AppModel,
        captureService: ClaudeUsageCaptureService = ClaudeUsageCaptureService(),
        parser: UsageScreenParser = UsageScreenParser()
    ) {
        self.appModel = appModel
        self.captureService = captureService
        self.parser = parser
    }
    func startIfNeeded() {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        reconfigureAutoRefresh()
    }

    func reconfigureAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.refresh(forceVisibleLoading: self.snapshot == nil)
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

    func refresh(forceVisibleLoading: Bool = true) async {
        if forceVisibleLoading || snapshot == nil {
            state = .loading
        }

        lastAttemptAt = .now
        lastErrorMessage = nil

        do {
            let capture = try await captureService.captureUsage()
            diagnosticsText = capture.screenText
            let parsedSnapshot = try parser.parse(
                screenText: capture.screenText,
                capturedAt: capture.capturedAt
            )

            snapshot = parsedSnapshot
            lastGoodSnapshot = parsedSnapshot
            sourceState = parsedSnapshot.isPartial ? .partial : capture.sourceState
            state = .loaded
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastErrorMessage = message
            diagnosticsText = diagnosticsText.isEmpty ? message : diagnosticsText

            if let lastGoodSnapshot {
                snapshot = lastGoodSnapshot
                sourceState = isSnapshotStale ? .stale : .partial
            } else {
                sourceState = mapSourceState(for: error)
            }

            state = .failed(message)
        }
    }

    var isRefreshing: Bool {
        state == .loading
    }

    var isSnapshotStale: Bool {
        guard let referenceDate = snapshot?.capturedAt ?? lastGoodSnapshot?.capturedAt else {
            return true
        }

        return Date().timeIntervalSince(referenceDate) > Double(appModel.staleThresholdMinutes * 60)
    }

    var freshnessText: String {
        guard let referenceDate = snapshot?.capturedAt ?? lastGoodSnapshot?.capturedAt else {
            return "No successful capture yet"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Updated \(formatter.localizedString(for: referenceDate, relativeTo: .now))"
    }

    var menuBarTitle: String {
        if isRefreshing && snapshot == nil {
            return "Claude…"
        }

        let displayPlanName = snapshot?.displayPlanName

        if let planName = displayPlanName, let metric = snapshot?.currentSession?.primaryMetricText {
            let shortPlan = planName.replacingOccurrences(of: "Claude ", with: "")
            return "\(shortPlan) \(metric)"
        }

        if let planName = displayPlanName {
            return planName.replacingOccurrences(of: "Claude ", with: "")
        }

        if let metric = snapshot?.currentSession?.primaryMetricText {
            return metric
        }

        return "Claude"
    }

    var menuBarSymbol: String {
        switch sourceState {
        case .live:
            return "gauge.open.with.lines.needle.33percent"
        case .partial, .stale:
            return "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        case .apiKeyMode, .authRequired, .unavailable:
            return "exclamationmark.triangle"
        }
    }

    private func mapSourceState(for error: Error) -> CaptureSourceState {
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
}

extension SubscriptionLimitSnapshot {
    var displayPlanName: String? {
        planName == "Unknown Plan" ? nil : planName
    }
}
