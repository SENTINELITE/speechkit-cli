import Foundation
import Testing
@testable import SpeechKitCLICore

@Suite("keys command")
struct KeysCommandTests {
    private func runner(
        _ store: InMemoryKeychainStore = InMemoryKeychainStore(),
        environment: [String: String] = [:]
    ) -> KeysRunner {
        KeysRunner(store: store, environment: environment, console: Console(verbosity: .quiet))
    }

    @Test("set stores a trimmed key and reports it redacted")
    func setStores() throws {
        let store = InMemoryKeychainStore()
        let message = try runner(store).set("  sk-live-914f2a\n", for: .grok)
        #expect(try store.read(for: .grok) == "sk-live-914f2a")
        #expect(message == "Stored a grok key (\u{2022}\u{2022}\u{2022}\u{2022}4f2a).")
    }

    @Test("set refuses an empty key")
    func setRefusesEmpty() {
        #expect(throws: CLIError.usage("The key is empty; nothing was stored.")) {
            _ = try runner().set("   \n ", for: .openai)
        }
    }

    @Test("Apple is rejected by every key operation")
    func appleRejected() {
        let store = InMemoryKeychainStore()
        let expected = CLIError.usage(KeysRunner.appleMessage)
        #expect(throws: expected) { _ = try runner(store).set("x", for: .apple) }
        #expect(throws: expected) { _ = try runner(store).get(.apple, reveal: false) }
        #expect(throws: expected) { _ = try runner(store).delete(.apple) }
        #expect(CLIError.usage(KeysRunner.appleMessage).localizedDescription == "apple needs no key")
    }

    @Test("get redacts unless --reveal is passed")
    func getRedacts() throws {
        let store = InMemoryKeychainStore(keys: [.openai: "sk-proj-00004f2a"])
        #expect(try runner(store).get(.openai, reveal: false) == "\u{2022}\u{2022}\u{2022}\u{2022}4f2a")
        #expect(try runner(store).get(.openai, reveal: true) == "sk-proj-00004f2a")
    }

    @Test("get and delete explain that nothing is stored")
    func missingKey() {
        #expect(throws: CLIError.self) { _ = try runner().get(.grok, reveal: false) }
        #expect(throws: CLIError.self) { _ = try runner().delete(.grok) }
    }

    @Test("delete removes the key")
    func deleteRemoves() throws {
        let store = InMemoryKeychainStore(keys: [.meta: "m"])
        #expect(try runner(store).delete(.meta) == "Deleted the meta key.")
        #expect(try store.read(for: .meta) == nil)
    }

    @Test("list shows every provider, stored keys, and environment overrides")
    func listTable() throws {
        let store = InMemoryKeychainStore(keys: [.grok: "g", .cohere: "c"])
        let text = try runner(store, environment: ["SPEECHKIT_OPENAI_API_KEY": "sk-env"]).list()
        #expect(text == """
        PROVIDER    STORED  ENVIRONMENT OVERRIDE
        elevenlabs  no      -
        aqua        no      -
        cohere      yes     -
        grok        yes     -
        openai      no      SPEECHKIT_OPENAI_API_KEY
        meta        no      -
        gemini      no      -
        fish-audio  no      -
        apple       n/a     -
        voz         n/a     -

        """)
    }

    @Test("A blank environment variable is not an override")
    func blankOverride() throws {
        let text = try runner(environment: ["SPEECHKIT_GROK_API_KEY": "   "]).list()
        #expect(text.contains("grok        no      -"))
    }

    @Test("keys subcommands parse")
    func parsing() throws {
        let set = try Keys.parseAsRoot(["set", "Grok", "--from-stdin"]) as? Keys.Set
        #expect(set?.provider == .grok)
        #expect(set?.fromStdin == true)

        let get = try Keys.parseAsRoot(["get", "openai", "--reveal"]) as? Keys.Get
        #expect(get?.provider == .openai)
        #expect(get?.reveal == true)

        let delete = try Keys.parseAsRoot(["delete", "meta"]) as? Keys.Delete
        #expect(delete?.provider == .meta)

        #expect(try Keys.parseAsRoot(["list"]) is Keys.List)
        #expect(try Keys.parseAsRoot([]) is Keys.List)
    }

    @Test("keys check parses with and without providers and flags")
    func checkParsing() throws {
        let bare = try Keys.parseAsRoot(["check"]) as? Keys.Check
        #expect(bare?.providers == [])
        #expect(bare?.live == false)
        #expect(bare?.json == false)

        let full = try Keys.parseAsRoot(["check", "openai", "grok", "--live", "--json"]) as? Keys.Check
        #expect(full?.providers == ["openai", "grok"])
        #expect(full?.live == true)
        #expect(full?.json == true)

        let everything = try Keys.parseAsRoot(["check", "all"]) as? Keys.Check
        #expect(everything?.providers == ["all"])
    }

    @Test("keys help mentions check")
    func helpMentionsCheck() {
        #expect(Keys.configuration.abstract.contains("check"))
        #expect(Keys.configuration.discussion.contains("keys check"))
        #expect(Keys.configuration.subcommands.contains { $0 == Keys.Check.self })
    }

    @Test("keys rejects an unknown provider")
    func parsingRejectsUnknownProvider() {
        #expect(throws: (any Error).self) {
            _ = try Keys.parseAsRoot(["set", "whisper"])
        }
    }

    @Test("--from-stdin is required when standard input is not a terminal")
    func stdinRequiredWhenPiped() throws {
        // The test runner's standard input is not a terminal, so the prompt path
        // is unreachable here and must say so rather than block.
        guard isatty(FileHandle.standardInput.fileDescriptor) != 1 else { return }
        #expect(throws: CLIError.self) {
            _ = try runner().readKey(for: .grok, fromStandardInput: false)
        }
    }
}
