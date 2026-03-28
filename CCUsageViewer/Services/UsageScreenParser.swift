import Foundation

protocol UsageScreenParserProtocol: Sendable {
    func parse(screenText: String, capturedAt: Date) throws -> SubscriptionLimitSnapshot
}

enum UsageScreenParserError: LocalizedError, Equatable {
    case missingUsageMarkers

    var errorDescription: String? {
        switch self {
        case .missingUsageMarkers:
            return "Claude returned a screen, but it did not look like the /usage view."
        }
    }
}

struct UsageScreenParser: UsageScreenParserProtocol, Sendable {
    func parse(screenText: String, capturedAt: Date) throws -> SubscriptionLimitSnapshot {
        let normalizedText = screenText
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        let lines = normalizedText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let lowercaseText = lines.joined(separator: "\n").lowercased()
        guard lowercaseText.contains("current session")
            || lowercaseText.contains("weekly")
            || lowercaseText.contains("remaining")
            || lowercaseText.contains("used") else {
            throw UsageScreenParserError.missingUsageMarkers
        }

        let planName = extractPlanName(from: lines) ?? "Unknown Plan"
        let currentSession = extractSection(named: "Current session", matching: "current session", from: lines)
        let weeklyLimit = extractWeeklySection(from: lines)
        let isPartial = currentSession == nil
            || (currentSession?.primaryMetricText == nil && currentSession?.progressPercent == nil)

        return SubscriptionLimitSnapshot(
            capturedAt: capturedAt,
            planName: planName,
            currentSession: currentSession,
            weeklyLimit: weeklyLimit,
            rawText: normalizedText.trimmingCharacters(in: .whitespacesAndNewlines),
            isPartial: isPartial
        )
    }

    private func extractPlanName(from lines: [String]) -> String? {
        let candidates = [
            #"(?i)\bclaude\s+(max|pro)\b"#,
            #"(?i)\b(max|pro)\s+plan\b"#
        ]

        for pattern in candidates {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }

            for line in lines where !line.isEmpty {
                let range = NSRange(location: 0, length: line.utf16.count)
                if let match = regex.firstMatch(in: line, options: [], range: range),
                   let resultRange = Range(match.range, in: line) {
                    let plan = String(line[resultRange])
                    return plan
                        .replacingOccurrences(of: "plan", with: "", options: .caseInsensitive)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .capitalized
                }
            }
        }

        return nil
    }

    private func extractSection(named title: String, matching keyword: String, from lines: [String]) -> LimitSection? {
        guard let startIndex = lines.firstIndex(where: { $0.localizedCaseInsensitiveContains(keyword) }) else {
            return nil
        }

        var sectionLines = [String]()
        var sawTitle = false

        for line in lines[startIndex...] {
            guard !line.isEmpty else {
                if sawTitle {
                    break
                }
                continue
            }

            if sawTitle, line.startsNewSection(excluding: keyword) {
                break
            }

            sawTitle = true
            sectionLines.append(line)

            if sectionLines.count >= 6 {
                break
            }
        }

        guard !sectionLines.isEmpty else {
            return nil
        }

        let usedText = firstMeaningfulLine(in: sectionLines, containingAny: ["used", "usage", "consumed"])
        let remainingText = firstMeaningfulLine(in: sectionLines, containingAny: ["remaining", "left"])
        let resetText = firstMeaningfulLine(in: sectionLines, containingAny: ["reset", "resets"])
        let progressPercent = sectionLines.lazy.compactMap { firstPercent(in: $0) }.first

        return LimitSection(
            title: title,
            usedText: usedText,
            remainingText: remainingText,
            progressPercent: progressPercent,
            resetText: resetText
        )
    }

    private func extractWeeklySection(from lines: [String]) -> LimitSection? {
        if let preferredSection = extractSection(
            named: "Current week",
            matching: "current week (all models)",
            from: lines
        ) {
            return preferredSection
        }

        if let currentWeekSection = extractSection(
            named: "Current week",
            matching: "current week",
            from: lines
        ) {
            return currentWeekSection
        }

        return extractSection(named: "Weekly limit", matching: "weekly", from: lines)
    }

    private func firstMeaningfulLine(in lines: [String], containingAny keywords: [String]) -> String? {
        lines.first { line in
            let lowercaseLine = line.lowercased()
            return keywords.contains(where: { lowercaseLine.contains($0) })
                && lowercaseLine != "current session"
                && lowercaseLine != "weekly"
                && lowercaseLine != "weekly limit"
        }
    }

    private func firstPercent(in line: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,3})%"#) else {
            return nil
        }

        let range = NSRange(location: 0, length: line.utf16.count)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: line),
              let value = Double(line[valueRange]) else {
            return nil
        }

        return min(max(value, 0), 100)
    }
}

private extension String {
    func startsNewSection(excluding currentKeyword: String) -> Bool {
        let lowercaseValue = lowercased()
        let sectionKeywords = ["current session", "weekly", "weekly limit", "plan"]
        return sectionKeywords.contains { keyword in
            keyword != currentKeyword
                && (lowercaseValue == keyword || lowercaseValue.hasPrefix("\(keyword) "))
        }
    }
}
