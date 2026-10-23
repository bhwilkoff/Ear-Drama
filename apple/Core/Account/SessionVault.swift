import Foundation
import Security

/// Where the Worker's session pair lives. Tokens never touch UserDefaults or a
/// file (AGENTS.md: secrets never in cleartext on disk).
nonisolated protocol SessionVault: Sendable {
    func load() -> WorkerSession?
    func save(_ session: WorkerSession)
    func clear()
}

/// The Keychain, this device only, readable after the first unlock so a
/// background sync can refresh.
nonisolated struct KeychainVault: SessionVault {
    var service = "app.eardrama.session"
    var account = "worker"

    private var query: [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        #if os(macOS)
        q[kSecUseDataProtectionKeychain as String] = true
        #endif
        return q
    }

    func load() -> WorkerSession? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(WorkerSession.self, from: data)
    }

    func save(_ session: WorkerSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = query
            add.merge(update) { $1 }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    func clear() {
        SecItemDelete(query as CFDictionary)
    }
}

/// For tests: the same contract with nothing persisted.
nonisolated final class MemoryVault: SessionVault, @unchecked Sendable {
    private let lock = NSLock()
    private var session: WorkerSession?

    init(_ session: WorkerSession? = nil) { self.session = session }

    func load() -> WorkerSession? { lock.withLock { session } }
    func save(_ session: WorkerSession) { lock.withLock { self.session = session } }
    func clear() { lock.withLock { session = nil } }
}
