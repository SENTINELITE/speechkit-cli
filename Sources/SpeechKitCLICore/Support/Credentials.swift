import Foundation
import SpeechKit

/// Supplies API keys from the macOS Keychain.
///
/// Phase 3 adds a `SecItem` backed implementation. The default does nothing, so
/// the flag and environment paths work today without a Keychain prompt.
public protocol KeychainCredentialSource: Sendable {
    /// Returns the stored API key for a provider, or `nil` when there is none.
    ///
    /// - Throws: Any error raised while reading the Keychain.
    func apiKey(for provider: CLIProvider) throws -> String?
}

/// A Keychain source that never finds a key.
public struct NoKeychainCredentialSource: KeychainCredentialSource {
    /// Creates the no-op source.
    public init() {}

    /// Returns `nil` for every provider.
    public func apiKey(for provider: CLIProvider) throws -> String? { nil }
}

/// Resolves the credential for a provider.
///
/// The order is `--api-key`, then `SPEECHKIT_<PROVIDER>_API_KEY`, then the
/// Keychain.
public struct CredentialResolver: Sendable {
    private let environment: [String: String]
    private let keychain: any KeychainCredentialSource

    /// Creates a resolver.
    ///
    /// - Parameters:
    ///   - environment: The environment to read. Tests pass a fixed dictionary.
    ///   - keychain: The Keychain source consulted last.
    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        keychain: any KeychainCredentialSource = NoKeychainCredentialSource()
    ) {
        self.environment = environment
        self.keychain = keychain
    }

    /// The environment variable that holds a provider's API key.
    public static func environmentVariableName(for provider: CLIProvider) -> String {
        "SPEECHKIT_\(provider.rawValue.uppercased())_API_KEY"
    }

    /// Returns the provider named by `SPEECHKIT_PROVIDER`, when it is set and valid.
    public func environmentProvider() -> CLIProvider? {
        guard let raw = environment["SPEECHKIT_PROVIDER"]?.trimmingCharacters(in: .whitespaces),
              !raw.isEmpty else {
            return nil
        }
        return CLIProvider(argument: raw)
    }

    /// Resolves the credential for a provider.
    ///
    /// - Parameters:
    ///   - provider: The provider being run.
    ///   - flagAPIKey: The value of `--api-key`, when it was passed.
    /// - Returns: The credential, or `nil` for providers that need none.
    /// - Throws: ``CLIError/missingCredential(_:)`` when a key is required and none was found.
    public func resolve(provider: CLIProvider, flagAPIKey: String? = nil) throws -> SpeechCredential? {
        guard provider != .apple else { return nil }

        if let key = nonEmpty(flagAPIKey) {
            return .apiKey(key)
        }
        if let key = nonEmpty(environment[Self.environmentVariableName(for: provider)]) {
            return .apiKey(key)
        }
        if let key = nonEmpty(try keychain.apiKey(for: provider)) {
            return .apiKey(key)
        }
        throw CLIError.missingCredential(provider)
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
