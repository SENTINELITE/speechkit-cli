import Foundation
import SpeechKit
import Testing
@testable import SpeechKitCLICore

@Suite("Credentials")
struct CredentialsTests {
    private struct StubKeychain: KeychainCredentialSource {
        var keys: [CLIProvider: String] = [:]
        func apiKey(for provider: CLIProvider) throws -> String? { keys[provider] }
    }

    @Test("Environment variable names follow SPEECHKIT_<PROVIDER>_API_KEY")
    func variableNames() {
        #expect(CredentialResolver.environmentVariableName(for: .openai) == "SPEECHKIT_OPENAI_API_KEY")
        #expect(CredentialResolver.environmentVariableName(for: .elevenlabs) == "SPEECHKIT_ELEVENLABS_API_KEY")
    }

    @Test("The flag wins over the environment and the Keychain")
    func flagWins() throws {
        let resolver = CredentialResolver(
            environment: ["SPEECHKIT_OPENAI_API_KEY": "env"],
            keychain: StubKeychain(keys: [.openai: "keychain"])
        )
        #expect(try resolver.resolve(provider: .openai, flagAPIKey: "flag") == .apiKey("flag"))
    }

    @Test("The environment wins over the Keychain")
    func environmentWins() throws {
        let resolver = CredentialResolver(
            environment: ["SPEECHKIT_GROK_API_KEY": "env"],
            keychain: StubKeychain(keys: [.grok: "keychain"])
        )
        #expect(try resolver.resolve(provider: .grok) == .apiKey("env"))
    }

    @Test("The Keychain is the last resort")
    func keychainLast() throws {
        let resolver = CredentialResolver(environment: [:], keychain: StubKeychain(keys: [.grok: "keychain"]))
        #expect(try resolver.resolve(provider: .grok) == .apiKey("keychain"))
    }

    @Test("Blank values are ignored")
    func blankValuesIgnored() throws {
        let resolver = CredentialResolver(
            environment: ["SPEECHKIT_GROK_API_KEY": "  "],
            keychain: StubKeychain(keys: [.grok: "keychain"])
        )
        #expect(try resolver.resolve(provider: .grok, flagAPIKey: "") == .apiKey("keychain"))
    }

    @Test("A missing credential exits with code three")
    func missingCredential() {
        let resolver = CredentialResolver(environment: [:])
        #expect(throws: CLIError.missingCredential(.openai)) {
            _ = try resolver.resolve(provider: .openai)
        }
        #expect(CLIError.missingCredential(.openai).exitCode == 3)
    }

    @Test("Apple needs no credential")
    func appleNeedsNoCredential() throws {
        let resolver = CredentialResolver(environment: [:])
        #expect(try resolver.resolve(provider: .apple) == nil)
    }

    @Test("All three sources resolve in order through the real store protocol")
    func threeSourcesInOrder() throws {
        let store = InMemoryKeychainStore(keys: [.grok: "keychain"])
        let resolver = CredentialResolver(
            environment: ["SPEECHKIT_GROK_API_KEY": "env"],
            keychain: store
        )
        #expect(try resolver.resolve(provider: .grok, flagAPIKey: "flag") == .apiKey("flag"))
        #expect(try resolver.resolve(provider: .grok) == .apiKey("env"))

        let keychainOnly = CredentialResolver(environment: [:], keychain: store)
        #expect(try keychainOnly.resolve(provider: .grok) == .apiKey("keychain"))

        try store.delete(for: .grok)
        #expect(throws: CLIError.missingCredential(.grok)) {
            _ = try keychainOnly.resolve(provider: .grok)
        }
    }

    @Test("SPEECHKIT_PROVIDER is read case-insensitively")
    func providerFromEnvironment() {
        #expect(CredentialResolver(environment: ["SPEECHKIT_PROVIDER": "OpenAI"]).environmentProvider() == .openai)
        #expect(CredentialResolver(environment: ["SPEECHKIT_PROVIDER": "nope"]).environmentProvider() == nil)
        #expect(CredentialResolver(environment: [:]).environmentProvider() == nil)
    }
}
