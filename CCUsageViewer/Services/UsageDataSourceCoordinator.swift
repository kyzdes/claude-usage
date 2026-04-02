import Foundation

protocol UsageDataSourceCoordinatorProtocol: Sendable {
    func fetchSnapshot() async throws -> SubscriptionLimitSnapshot
}

enum DataSourceCoordinatorError: LocalizedError {
    case allSourcesFailed(apiError: Error?, ptyError: Error?)

    var errorDescription: String? {
        switch self {
        case .allSourcesFailed(let apiError, let ptyError):
            var parts: [String] = []
            if let apiError { parts.append("API: \(apiError.localizedDescription)") }
            if let ptyError { parts.append("PTY: \(ptyError.localizedDescription)") }
            return "All data sources failed. \(parts.joined(separator: "; "))"
        }
    }
}

struct UsageDataSourceCoordinator: UsageDataSourceCoordinatorProtocol, Sendable {
    let preference: DataSourcePreference
    let sessionKeyStorage: SessionKeyStorageProtocol
    let apiService: ClaudeAPIServiceProtocol
    let responseMapper: ClaudeAPIResponseMapper
    let claudeCaptureService: ClaudeUsageCaptureServiceProtocol
    let claudeParser: UsageScreenParserProtocol

    func fetchSnapshot() async throws -> SubscriptionLimitSnapshot {
        switch preference {
        case .api:
            return try await fetchViaAPI()
        case .ptyCapture:
            return try await fetchViaPTY()
        case .autoFallback:
            return try await fetchWithFallback()
        }
    }

    private func fetchWithFallback() async throws -> SubscriptionLimitSnapshot {
        // Try API first if credentials exist
        if let sessionKey = sessionKeyStorage.getSessionKey(),
           let orgId = sessionKeyStorage.getOrganizationId() {
            do {
                return try await fetchViaAPI(sessionKey: sessionKey, orgId: orgId)
            } catch {
                // Fall through to PTY
                return try await fetchViaPTYWithFallback(apiError: error)
            }
        }

        // No API credentials — go straight to PTY
        return try await fetchViaPTY()
    }

    private func fetchViaAPI() async throws -> SubscriptionLimitSnapshot {
        guard let sessionKey = sessionKeyStorage.getSessionKey(),
              let orgId = sessionKeyStorage.getOrganizationId() else {
            throw ClaudeAPIError.invalidSessionKey
        }
        return try await fetchViaAPI(sessionKey: sessionKey, orgId: orgId)
    }

    private func fetchViaAPI(sessionKey: String, orgId: String) async throws -> SubscriptionLimitSnapshot {
        async let usageResult = apiService.fetchUsage(sessionKey: sessionKey, organizationId: orgId)
        async let overageResult = try? apiService.fetchOverage(sessionKey: sessionKey, organizationId: orgId)
        async let prepaidResult = try? apiService.fetchPrepaid(sessionKey: sessionKey, organizationId: orgId)

        let usage = try await usageResult
        let overage = await overageResult
        let prepaid = await prepaidResult

        return responseMapper.map(usage: usage, overage: overage, prepaid: prepaid)
    }

    private func fetchViaPTY() async throws -> SubscriptionLimitSnapshot {
        let captureResult = try await claudeCaptureService.captureUsage()
        var snapshot = try claudeParser.parse(
            screenText: captureResult.screenText,
            capturedAt: captureResult.capturedAt
        )
        snapshot = snapshot.applyingPlanHint(captureResult.observedPlanName)
        return snapshot
    }

    private func fetchViaPTYWithFallback(apiError: Error) async throws -> SubscriptionLimitSnapshot {
        do {
            return try await fetchViaPTY()
        } catch let ptyError {
            throw DataSourceCoordinatorError.allSourcesFailed(
                apiError: apiError,
                ptyError: ptyError
            )
        }
    }
}
