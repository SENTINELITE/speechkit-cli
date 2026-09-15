import Foundation
import Security

/// Reads and writes provider API keys.
///
/// The tool talks to storage through this protocol so tests can substitute an
/// in-memory double and never touch the login keychain.
public protocol KeychainStoring: KeychainCredentialSource {
    /// Stores an API key for a provider, replacing any existing entry.
    ///
    /// - Throws: ``CLIError/keychainFailure(_:)`` when the write fails.
    func save(_ apiKey: String, for provider: CLIProvider) throws

    /// Returns the stored API key for a provider, or `nil` when there is none.
    ///
    /// - Throws: ``CLIError/keychainFailure(_:)`` when the read fails.
    func read(for provider: CLIProvider) throws -> String?

    /// Removes the stored API key for a provider.
    ///
    /// - Returns: `true` when an entry was removed, `false` when there was none.
    /// - Throws: ``CLIError/keychainFailure(_:)`` when the delete fails.
    @discardableResult
    func delete(for provider: CLIProvider) throws -> Bool

    /// Returns every provider that currently has a stored key, in enum order.
    ///
    /// - Throws: ``CLIError/keychainFailure(_:)`` when the query fails.
    func list() throws -> [CLIProvider]
}

extension KeychainStoring {
    /// Satisfies ``KeychainCredentialSource`` by reading the stored key.
    public func apiKey(for provider: CLIProvider) throws -> String? {
        try read(for: provider)
    }
}

/// A `SecItem` backed store for provider API keys.
///
/// Keys live as generic passwords under one service, with the provider raw
/// value as the account, so `security find-generic-password -s
/// com.sentinelite.speechkit-cli` lists everything the tool stored. Items are
/// accessible after the first unlock and never migrate to another device.
public struct KeychainStore: KeychainStoring {
    /// The keychain service every `speechkit` item is filed under.
    public static let defaultService = "com.sentinelite.speechkit-cli"

    /// The service this store reads and writes.
    public let service: String

    /// Creates a store.
    ///
    /// - Parameter service: The keychain service. Tests that must exercise the
    ///   real keychain pass a throwaway value.
    public init(service: String = KeychainStore.defaultService) {
        self.service = service
    }

    /// Stores an API key, replacing any existing entry for the provider.
    public func save(_ apiKey: String, for provider: CLIProvider) throws {
        let query = baseQuery(account: provider.rawValue)
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = Data(apiKey.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CLIError.keychainFailure(Self.message(for: status, action: "store the key"))
        }
    }

    /// Returns the stored API key for a provider, or `nil` when there is none.
    public func read(for provider: CLIProvider) throws -> String? {
        var query = baseQuery(account: provider.rawValue)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw CLIError.keychainFailure(Self.message(for: status, action: "read the key"))
        }
        return String(data: data, encoding: .utf8)
    }

    /// Removes the stored API key for a provider.
    @discardableResult
    public func delete(for provider: CLIProvider) throws -> Bool {
        let status = SecItemDelete(baseQuery(account: provider.rawValue) as CFDictionary)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else {
            throw CLIError.keychainFailure(Self.message(for: status, action: "delete the key"))
        }
        return true
    }

    /// Returns every provider that currently has a stored key, in enum order.
    public func list() throws -> [CLIProvider] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        query[kSecReturnData as String] = false

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            throw CLIError.keychainFailure(Self.message(for: status, action: "list stored keys"))
        }

        let accounts = Set(items.compactMap { $0[kSecAttrAccount as String] as? String })
        return CLIProvider.allCases.filter { accounts.contains($0.rawValue) }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func message(for status: OSStatus, action: String) -> String {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
        return "Could not \(action): \(detail)"
    }
}

/// An in-memory store, for tests and for runs that must not touch the keychain.
public final class InMemoryKeychainStore: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [CLIProvider: String]

    /// Creates a store holding the given keys.
    public init(keys: [CLIProvider: String] = [:]) {
        self.keys = keys
    }

    /// Stores an API key for a provider.
    public func save(_ apiKey: String, for provider: CLIProvider) throws {
        lock.withLock { keys[provider] = apiKey }
    }

    /// Returns the stored API key for a provider, or `nil` when there is none.
    public func read(for provider: CLIProvider) throws -> String? {
        lock.withLock { keys[provider] }
    }

    /// Removes the stored API key for a provider.
    @discardableResult
    public func delete(for provider: CLIProvider) throws -> Bool {
        lock.withLock { keys.removeValue(forKey: provider) != nil }
    }

    /// Returns every provider that currently has a stored key, in enum order.
    public func list() throws -> [CLIProvider] {
        let stored = lock.withLock { Set(keys.keys) }
        return CLIProvider.allCases.filter { stored.contains($0) }
    }
}

extension String {
    /// Returns the key with everything but its last four characters replaced by bullets.
    ///
    /// Short keys are shown as bullets alone, so a four-character secret is not
    /// printed in full by a command whose job is to hide it.
    public var redactedAPIKey: String {
        let visible = 4
        guard count > visible else { return String(repeating: "\u{2022}", count: 8) }
        return String(repeating: "\u{2022}", count: visible) + String(suffix(visible))
    }
}
