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
/// The order is `--api-key`, then `SPEECHKIT_<PROVIDER>_API_KEY` (and any
/// vendor variable the provider also answers to, such as `FISH_API_KEY`), then
/// the Keychain.
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
    ///
    /// A hyphen in the raw value becomes an underscore, because shells reject
    /// hyphens in variable names: `fish-audio` reads `SPEECHKIT_FISH_AUDIO_API_KEY`.
    public static func environmentVariableName(for provider: CLIProvider) -> String {
        let name = provider.rawValue.uppercased().replacingOccurrences(of: "-", with: "_")
        return "SPEECHKIT_\(name)_API_KEY"
    }

    /// Every environment variable a provider's API key is read from, in order.
    ///
    /// The `SPEECHKIT_` variable always comes first. Fish Audio also answers to
    /// `FISH_API_KEY`, the name its own SDKs and SpeechKit's live tests use.
    public static func environmentVariableNames(for provider: CLIProvider) -> [String] {
        var names = [environmentVariableName(for: provider)]
        if provider == .fishAudio {
            names.append("FISH_API_KEY")
        }
        return names
    }

    /// Returns the first non-blank key a provider's variables hold, and the variable it came from.
    ///
    /// - Parameters:
    ///   - provider: The provider whose variables are read.
    ///   - environment: The environment to read.
    public static func environmentKey(
        for provider: CLIProvider,
        in environment: [String: String]
    ) -> (variable: String, key: String)? {
        for variable in environmentVariableNames(for: provider) {
            let value = environment[variable]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !value.isEmpty {
                return (variable, value)
            }
        }
        return nil
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
        guard provider.requiresCredential else { return nil }

        if let key = nonEmpty(flagAPIKey) {
            return .apiKey(key)
        }
        if let found = Self.environmentKey(for: provider, in: environment) {
            return .apiKey(found.key)
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
