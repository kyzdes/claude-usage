import Foundation

enum CaptureFlowPhase: String, Sendable {
    case launching
    case awaitingTrustPrompt
    case awaitingReadyPrompt
    case requestingUsage
    case awaitingUsageScreen
    case captured
    case failed
}

enum CaptureFlowAction: Equatable, Sendable {
    case sendTrust
    case sendUsage
    case captureCompleted
}

struct CaptureFlowStateMachine: Sendable {
    private(set) var phase: CaptureFlowPhase
    private(set) var phaseEnteredAt: Date
    private(set) var lastScreenChangeAt: Date

    private var lastNormalizedScreen = ""
    private var didSendTrust = false
    private var didSendUsage = false
    private var trustSendCount = 0

    init(now: Date = .now) {
        self.phase = .launching
        self.phaseEnteredAt = now
        self.lastScreenChangeAt = now
    }

    mutating func evaluate(screenText: String, now: Date) -> [CaptureFlowAction] {
        let normalizedScreen = screenText.normalizedTerminalText()
        if normalizedScreen != lastNormalizedScreen {
            lastNormalizedScreen = normalizedScreen
            lastScreenChangeAt = now
        }

        if phase == .launching, !normalizedScreen.isEmpty {
            transition(to: .awaitingTrustPrompt, at: now)
        }

        switch phase {
        case .launching:
            return []
        case .awaitingTrustPrompt:
            if normalizedScreen.containsTrustPrompt, !didSendTrust {
                didSendTrust = true
                trustSendCount = 1
                transition(to: .awaitingReadyPrompt, at: now)
                return [.sendTrust]
            }

            if !normalizedScreen.containsTrustPrompt,
               now.timeIntervalSince(phaseEnteredAt) >= 1.0,
               !didSendUsage {
                didSendUsage = true
                transition(to: .awaitingUsageScreen, at: now)
                return [.sendUsage]
            }

            return []
        case .awaitingReadyPrompt:
            if normalizedScreen.containsTrustPrompt,
               trustSendCount < 2,
               now.timeIntervalSince(phaseEnteredAt) >= 1.0 {
                trustSendCount += 1
                transition(to: .awaitingReadyPrompt, at: now)
                return [.sendTrust]
            }

            if now.timeIntervalSince(phaseEnteredAt) >= 2.5,
               !didSendUsage {
                didSendUsage = true
                transition(to: .awaitingUsageScreen, at: now)
                return [.sendUsage]
            }

            return []
        case .requestingUsage:
            if !didSendUsage {
                didSendUsage = true
                transition(to: .awaitingUsageScreen, at: now)
                return [.sendUsage]
            }

            return []
        case .awaitingUsageScreen:
            if normalizedScreen.containsUsageMarkers,
               now.timeIntervalSince(lastScreenChangeAt) >= 1.0 {
                transition(to: .captured, at: now)
                return [.captureCompleted]
            }

            return []
        case .captured, .failed:
            return []
        }
    }

    mutating func markFailed(at now: Date) {
        transition(to: .failed, at: now)
    }

    private mutating func transition(to phase: CaptureFlowPhase, at now: Date) {
        self.phase = phase
        self.phaseEnteredAt = now
    }
}

private extension String {
    var containsTrustPrompt: Bool {
        let haystack = lowercased()
        return haystack.contains("yes, i trust this folder") || haystack.contains("quick safety check")
    }

    var looksReadyForCommand: Bool {
        let haystack = lowercased()
        return haystack.contains("claude code")
            || haystack.contains("claude max")
            || haystack.contains("accept edits")
            || haystack.contains("for shortcuts")
            || haystack.contains("what's new")
    }

    var containsUsageMarkers: Bool {
        let haystack = lowercased()
        let keywords = [
            "current session",
            "weekly",
            "reset",
            "remaining",
            "used",
            "plan"
        ]

        let matches = keywords.filter { haystack.contains($0) }
        return matches.count >= 2 || haystack.contains("current session")
    }

    func normalizedTerminalText() -> String {
        lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
