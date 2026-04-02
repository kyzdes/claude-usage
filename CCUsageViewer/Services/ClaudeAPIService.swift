import Foundation

protocol ClaudeAPIServiceProtocol: Sendable {
    func fetchOrganizations(sessionKey: String) async throws -> [ClaudeAPIOrganization]
    func fetchUsage(sessionKey: String, organizationId: String) async throws -> ClaudeAPIUsageResponse
    func fetchOverage(sessionKey: String, organizationId: String) async throws -> ClaudeAPIOverageResponse
    func fetchPrepaid(sessionKey: String, organizationId: String) async throws -> ClaudeAPIPrepaidResponse
}

enum ClaudeAPIError: LocalizedError, Equatable {
    case invalidSessionKey
    case cloudflareBlocked(String)
    case networkError(String)
    case decodingError(String)
    case missingOrganization
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidSessionKey:
            return "Session key is invalid or expired. Please log in again."
        case .cloudflareBlocked(let detail):
            return "Blocked by Cloudflare: \(detail)"
        case .networkError(let detail):
            return "Network error: \(detail)"
        case .decodingError(let detail):
            return "Failed to parse API response: \(detail)"
        case .missingOrganization:
            return "No organization found for this account."
        case .httpError(let code):
            return "HTTP error \(code)"
        }
    }
}

struct ClaudeAPIService: ClaudeAPIServiceProtocol, Sendable {
    private static let baseURL = "https://claude.ai/api"
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchOrganizations(sessionKey: String) async throws -> [ClaudeAPIOrganization] {
        let url = URL(string: "\(Self.baseURL)/organizations")!
        let data = try await fetchRaw(url: url, sessionKey: sessionKey)

        // Parse manually — the response may have many fields we don't care about
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ClaudeAPIError.decodingError("Organizations response is not a JSON array")
        }

        return array.map { dict in
            ClaudeAPIOrganization(
                uuid: dict["uuid"] as? String,
                id: dict["id"] as? String,
                name: dict["name"] as? String
            )
        }
    }

    func fetchUsage(sessionKey: String, organizationId: String) async throws -> ClaudeAPIUsageResponse {
        let url = URL(string: "\(Self.baseURL)/organizations/\(organizationId)/usage")!
        return try await fetch(url: url, sessionKey: sessionKey)
    }

    func fetchOverage(sessionKey: String, organizationId: String) async throws -> ClaudeAPIOverageResponse {
        let url = URL(string: "\(Self.baseURL)/organizations/\(organizationId)/overage_spend_limit")!
        return try await fetch(url: url, sessionKey: sessionKey)
    }

    func fetchPrepaid(sessionKey: String, organizationId: String) async throws -> ClaudeAPIPrepaidResponse {
        let url = URL(string: "\(Self.baseURL)/organizations/\(organizationId)/prepaid/credits")!
        return try await fetch(url: url, sessionKey: sessionKey)
    }

    private func fetchRaw(url: URL, sessionKey: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClaudeAPIError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.networkError("Invalid response type")
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            let body = String(data: data, encoding: .utf8) ?? ""
            if body.contains("Just a moment") || body.contains("Enable JavaScript") {
                throw ClaudeAPIError.cloudflareBlocked(String(body.prefix(200)))
            }
            throw ClaudeAPIError.invalidSessionKey
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ClaudeAPIError.httpError(httpResponse.statusCode)
        }

        if let bodyString = String(data: data, encoding: .utf8),
           bodyString.contains("Just a moment") || bodyString.contains("<html") {
            throw ClaudeAPIError.cloudflareBlocked(String(bodyString.prefix(200)))
        }

        return data
    }

    private func fetch<T: Decodable>(url: URL, sessionKey: String) async throws -> T {
        let data = try await fetchRaw(url: url, sessionKey: sessionKey)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ClaudeAPIError.decodingError(error.localizedDescription)
        }
    }
}
