import Foundation

protocol SessionKeyStorageProtocol: Sendable {
    func getSessionKey() -> String?
    func setSessionKey(_ value: String) throws
    func deleteSessionKey() throws
    func getOrganizationId() -> String?
    func setOrganizationId(_ value: String)
    func deleteOrganizationId()
}

struct SessionKeyStorage: SessionKeyStorageProtocol, Sendable {
    private static let sessionKeyKey = "credentials.sessionKey"
    private static let orgIdKey = "credentials.organizationId"

    func getSessionKey() -> String? {
        UserDefaults.standard.string(forKey: Self.sessionKeyKey)
    }

    func setSessionKey(_ value: String) throws {
        UserDefaults.standard.set(value, forKey: Self.sessionKeyKey)
    }

    func deleteSessionKey() throws {
        UserDefaults.standard.removeObject(forKey: Self.sessionKeyKey)
    }

    func getOrganizationId() -> String? {
        UserDefaults.standard.string(forKey: Self.orgIdKey)
    }

    func setOrganizationId(_ value: String) {
        UserDefaults.standard.set(value, forKey: Self.orgIdKey)
    }

    func deleteOrganizationId() {
        UserDefaults.standard.removeObject(forKey: Self.orgIdKey)
    }
}
