import Foundation
import Testing
@testable import SpeechKitCLICore

@Suite("Keychain store")
struct KeychainStoreTests {
    @Test("Saving, reading, and deleting round-trips through the store")
    func roundTrip() throws {
        let store = InMemoryKeychainStore()
        #expect(try store.read(for: .grok) == nil)

        try store.save("sk-grok-0001", for: .grok)
        #expect(try store.read(for: .grok) == "sk-grok-0001")

        try store.save("sk-grok-0002", for: .grok)
        #expect(try store.read(for: .grok) == "sk-grok-0002")

        #expect(try store.delete(for: .grok))
        #expect(try store.read(for: .grok) == nil)
        #expect(try store.delete(for: .grok) == false)
    }

    @Test("Listing returns stored providers in enum order")
    func listing() throws {
        let store = InMemoryKeychainStore()
        try store.save("b", for: .openai)
        try store.save("a", for: .elevenlabs)
        try store.save("c", for: .apple)
        #expect(try store.list() == [.elevenlabs, .openai, .apple])
    }

    @Test("A store is also a credential source")
    func credentialSource() throws {
        let store = InMemoryKeychainStore(keys: [.meta: "meta-key"])
        #expect(try store.apiKey(for: .meta) == "meta-key")
        #expect(try store.apiKey(for: .gemini) == nil)
    }

    @Test("Redaction keeps only the last four characters")
    func redaction() {
        #expect("sk-abcdef4f2a".redactedAPIKey == "\u{2022}\u{2022}\u{2022}\u{2022}4f2a")
        #expect("test-key".redactedAPIKey == "\u{2022}\u{2022}\u{2022}\u{2022}-key")
        #expect("abcd".redactedAPIKey == String(repeating: "\u{2022}", count: 8))
        #expect("ab".redactedAPIKey == String(repeating: "\u{2022}", count: 8))
    }

    @Test("The real store files items under the documented service")
    func serviceName() {
        #expect(KeychainStore.defaultService == "com.sentinelite.speechkit-cli")
        #expect(KeychainStore().service == "com.sentinelite.speechkit-cli")
    }
}
