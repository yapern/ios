import Foundation
import Observation
import Security

@MainActor
protocol SessionStorage {
    func read() throws -> Data?
    func write(_ data: Data?) throws
}

struct KeychainSessionStorage: SessionStorage {
    private let identity: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.yapern.api-session",
        kSecAttrAccount as String: "https://api.yapern.com",
    ]

    func read() throws -> Data? {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StorageError.unavailable }
        return result as? Data
    }

    func write(_ data: Data?) throws {
        guard let data else {
            let status = SecItemDelete(identity as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw StorageError.unavailable }
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = identity.merging(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw StorageError.unavailable }
    }

    private enum StorageError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Couldn’t access your saved sign-in. Please try again." }
    }
}

@MainActor @Observable
final class AccountStore {
    private(set) var session: AccountSession?
    private(set) var profileName = ""
    private(set) var isBusy = false
    private(set) var sessionError: String?
    private var checkingSession = false
    let api: MessageAPI
    private let storage: any SessionStorage

    var isSignedIn: Bool { session?.isValid == true }
    var userID: String? { isSignedIn ? session?.user.id : nil }

    init(api: MessageAPI = MessageAPI(), storage: (any SessionStorage)? = nil) {
        self.api = api
        let storage = storage ?? KeychainSessionStorage()
        self.storage = storage
        do {
            if let data = try storage.read() {
                // Keychain uses Codable’s matching default date representation.
                if let restored = try? JSONDecoder().decode(AccountSession.self, from: data), restored.isValid {
                    session = restored
                } else {
                    try storage.write(nil)
                }
            }
        } catch { sessionError = error.localizedDescription }
    }

    func signIn(email: String, password: String) async throws {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        let result = try await api.signIn(email: email, password: password)
        try storage.write(JSONEncoder().encode(result))
        session = result
        sessionError = nil
        profileName = ""
    }

    func validateSession() async {
        guard let current = session, !checkingSession else { return }
        checkingSession = true
        defer { checkingSession = false }
        do {
            guard current.isValid else { throw MessageAPIError.sessionExpired }
            let checked = try await api.checkSession(current)
            guard session?.token == current.token else { return }
            try storage.write(JSONEncoder().encode(checked))
            session = checked
            sessionError = nil
        } catch MessageAPIError.sessionExpired {
            if session?.token == current.token { clearExpiredSession() }
        } catch {
            if session?.token == current.token { sessionError = error.localizedDescription }
        }
    }

    func authenticated<Value>(_ action: (AccountSession) async throws -> Value) async throws -> Value {
        guard let current = session, current.isValid else {
            clearExpiredSession()
            throw MessageAPIError.sessionExpired
        }
        do {
            let result = try await action(current)
            guard session?.token == current.token else { throw MessageAPIError.notice("Your sign-in changed. Reload before trying again.") }
            return result
        }
        catch MessageAPIError.sessionExpired {
            if session?.token == current.token { clearExpiredSession() }
            throw MessageAPIError.sessionExpired
        }
    }

    func loadProfile() async throws {
        let profile = try await authenticated { try await api.fetchProfile($0) }
        profileName = profile.name
    }

    func saveName(_ name: String) async throws {
        let profile = try await authenticated { try await api.updateName(name, current: $0) }
        profileName = profile.name
    }

    func signOut() async throws {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        if let current = session {
            do { try await api.signOut(current) }
            catch MessageAPIError.sessionExpired { /* Already revoked. */ }
        }
        try storage.write(nil)
        session = nil
        profileName = ""
        sessionError = nil
    }

    private func clearExpiredSession() {
        session = nil
        profileName = ""
        sessionError = "Your session has expired. Sign in again to continue."
        do { try storage.write(nil) }
        catch { sessionError = error.localizedDescription }
    }
}
