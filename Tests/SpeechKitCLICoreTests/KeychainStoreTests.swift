import Foundation
import Security
import Testing
@testable import SpeechKitCLICore

@Suite("Keychain store")
struct KeychainStoreTests {
    @Test("Saves are unlocked-only, device-only, and never synchronized", arguments: [false, true])
    func saveProtection(_ exists: Bool) throws {
        let store = KeychainStore(
            updateItem: { query, attributes in
                #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
                #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
                #expect(attributes[kSecAttrSynchronizable as String] as? Bool == false)
                #expect(attributes[kSecValueData as String] as? Data == Data("dummy".utf8))
                return exists ? errSecSuccess : errSecItemNotFound
            },
            addItem: { attributes in
                #expect(!exists)
                #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
                #expect(attributes[kSecAttrSynchronizable as String] as? Bool == false)
                #expect(attributes[kSecAttrService as String] as? String == KeychainStore.defaultService)
                return errSecSuccess
            },
            deleteItem: { _ in Issue.record("Saving must not delete the old key"); return errSecSuccess }
        )
        try store.save("dummy", for: .openai)
    }

    @Test("Failed updates preserve the old item and report the status")
    func failedUpdate() {
        let store = KeychainStore(
            updateItem: { _, _ in errSecInteractionNotAllowed },
            addItem: { _ in Issue.record("A failed update must not add an item"); return errSecSuccess },
            deleteItem: { _ in Issue.record("A failed update must not delete an item"); return errSecSuccess }
        )
        let error = #expect(throws: CLIError.self) { try store.save("dummy", for: .openai) }
        #expect(error?.exitCode == 3)
        #expect(error?.localizedDescription.contains("dummy") == false)
    }

    @Test("Failed inserts report the status", arguments: [errSecAuthFailed, errSecDuplicateItem])
    func failedInsert(_ status: OSStatus) {
        let store = KeychainStore(
            updateItem: { _, _ in errSecItemNotFound },
            addItem: { _ in status },
            deleteItem: { _ in Issue.record("Saving must not delete an item"); return errSecSuccess }
        )
        let error = #expect(throws: CLIError.self) { try store.save("dummy", for: .openai) }
        #expect(error?.exitCode == 3)
    }

    @Test("Deletes check every status", arguments: [errSecSuccess, errSecItemNotFound, errSecAuthFailed])
    func deleteStatuses(_ status: OSStatus) throws {
        let store = KeychainStore(
            updateItem: { _, _ in Issue.record("Delete must not update"); return errSecSuccess },
            addItem: { _ in Issue.record("Delete must not add"); return errSecSuccess },
            deleteItem: { query in
                #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
                return status
            }
        )
        if status == errSecAuthFailed {
            #expect(throws: CLIError.self) { try store.delete(for: .openai) }
        } else {
            #expect(try store.delete(for: .openai) == (status == errSecSuccess))
        }
    }

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
