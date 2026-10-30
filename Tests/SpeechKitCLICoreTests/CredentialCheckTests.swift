import Foundation
import SpeechKit
import Testing
@testable import SpeechKitCLICore

@Suite("keys check")
struct CredentialCheckTests {
    /// An environment with one key, a keychain with another, and nothing else.
    private func check(
        environment: [String: String] = ["SPEECHKIT_OPENAI_API_KEY": "sk-proj-00004f2a"],
        keys: [CLIProvider: String] = [.grok: "xai-0000beef"]
    ) -> CredentialCheck {
        CredentialCheck(environment: environment, store: InMemoryKeychainStore(keys: keys))
    }

    // MARK: - Provider selection

    @Test("no argument and 'all' both mean every provider")
    func selectionDefaults() throws {
        #expect(try CredentialCheck.providers(named: []) == CLIProvider.allCases)
        #expect(try CredentialCheck.providers(named: ["all"]) == CLIProvider.allCases)
        #expect(try CredentialCheck.providers(named: ["openai", "all"]) == CLIProvider.allCases)
    }

    @Test("named providers are filtered, deduplicated, and kept in enum order")
    func selectionFilters() throws {
        let selected = try CredentialCheck.providers(named: ["openai", "Grok", "openai"])
        #expect(selected == [.grok, .openai])
    }

    @Test("an unknown provider name is a usage error")
    func selectionRejectsUnknown() {
        #expect(throws: CLIError.self) {
            _ = try CredentialCheck.providers(named: ["whisper"])
        }
    }

    // MARK: - Presence

    @Test("the presence table mixes env, keychain, none, and not needed")
    func presenceTable() {
        let rows = check().rows(for: [.openai, .grok, .aqua, .apple, .voz])
        let text = CredentialCheck.table(rows, live: false)
        #expect(text == """
        PROVIDER  SOURCE      ENV VAR                   KEY
        openai    env         SPEECHKIT_OPENAI_API_KEY  \u{2022}\u{2022}\u{2022}\u{2022}4f2a
        grok      keychain    SPEECHKIT_GROK_API_KEY    \u{2022}\u{2022}\u{2022}\u{2022}beef
        aqua      none        SPEECHKIT_AQUA_API_KEY    -
        apple     not needed  -                         -
        voz       not needed  -                         -

        """)
    }

    @Test("a blank environment variable falls through to the keychain")
    func blankEnvironmentFallsThrough() {
        let subject = check(
            environment: ["SPEECHKIT_GROK_API_KEY": "   "],
            keys: [.grok: "xai-0000beef"]
        )
        #expect(subject.rows(for: [.grok]).first?.source == .keychain)
    }

    @Test("keys are never printed in full")
    func redaction() {
        let rows = check().rows(for: [.openai, .grok])
        #expect(rows[0].key == "\u{2022}\u{2022}\u{2022}\u{2022}4f2a")
        #expect(rows[1].key == "\u{2022}\u{2022}\u{2022}\u{2022}beef")
        for row in rows {
            #expect(row.key?.contains("sk-proj") == false)
            #expect(row.key?.contains("xai-") == false)
        }
        let text = CredentialCheck.table(rows, live: false)
        #expect(!text.contains("sk-proj-00004f2a"))
        #expect(!text.contains("xai-0000beef"))
    }

    @Test("a short key is hidden entirely")
    func redactionOfShortKey() {
        let subject = check(environment: [:], keys: [.meta: "abcd"])
        #expect(subject.rows(for: [.meta]).first?.key == String(repeating: "\u{2022}", count: 8))
    }

    // MARK: - Exit codes

    @Test("presence exits 0 when every requested key is present")
    func exitZeroWhenComplete() {
        let rows = check().rows(for: [.openai, .grok, .apple, .voz])
        #expect(CredentialCheck.exitCode(rows) == 0)
        #expect(CredentialCheck.summary(rows) == nil)
    }

    @Test("presence exits 3 and summarises the missing keys")
    func exitThreeWhenMissing() {
        let rows = check().rows(for: CLIProvider.allCases)
        #expect(CredentialCheck.exitCode(rows) == 3)
        #expect(CredentialCheck.summary(rows) == """
        6 of 8 providers have no key: elevenlabs, aqua, cohere, meta, gemini, fish-audio. \
        Run 'speechkit keys set <provider>'.
        """)
    }

    @Test("a keyless provider alone exits 0 with no summary")
    func keylessOnly() {
        let rows = check().rows(for: [.apple, .voz])
        #expect(CredentialCheck.exitCode(rows) == 0)
        #expect(CredentialCheck.summary(rows) == nil)
    }

    @Test("a failed probe exits 2, and a missing key still exits 3")
    func liveExitCodes() {
        let ok = CredentialCheckRow(
            provider: "apple", source: .notNeeded, environmentVariable: nil, key: nil,
            status: .ok, seconds: 0.4
        )
        let failed = CredentialCheckRow(
            provider: "openai", source: .environment, environmentVariable: "SPEECHKIT_OPENAI_API_KEY",
            key: "\u{2022}\u{2022}\u{2022}\u{2022}4f2a", status: .failed, seconds: 0.3, detail: "401"
        )
        let missing = CredentialCheckRow(
            provider: "aqua", source: .notFound, environmentVariable: "SPEECHKIT_AQUA_API_KEY",
            key: nil, status: .skipped, detail: "no key"
        )
        #expect(CredentialCheck.exitCode([ok]) == 0)
        #expect(CredentialCheck.exitCode([ok, failed]) == 2)
        #expect(CredentialCheck.exitCode([ok, missing]) == 3)
        #expect(CredentialCheck.exitCode([ok, failed, missing]) == 3)
        #expect(CredentialCheck.failureSummary([ok, failed]) == "1 provider failed the live check: openai.")
    }

    // MARK: - Live, with a fake probe

    /// A probe that never leaves the process.
    private func fakeProbe(
        _ outcomes: [CLIProvider: CredentialCheck.ProbeResult]
    ) -> CredentialCheck.Probe {
        { provider, _ in
            outcomes[provider] ?? CredentialCheck.ProbeResult(status: .ok, seconds: 0.1)
        }
    }

    @Test("--live reports ok, failed, and skipped rows")
    func liveRows() async {
        let probe = fakeProbe([
            .openai: CredentialCheck.ProbeResult(status: .ok, seconds: 1.25),
            .grok: CredentialCheck.ProbeResult(
                status: .failed,
                seconds: 0.44,
                detail: "Incorrect API key provided."
            ),
            .voz: CredentialCheck.ProbeResult(status: .skipped, seconds: 0.0, detail: "model not downloaded")
        ])
        let rows = await check().liveRows(for: [.openai, .grok, .aqua, .apple, .voz], probe: probe)

        #expect(rows.map(\.provider) == ["openai", "grok", "aqua", "apple", "voz"])
        #expect(rows.map { $0.status } == [.ok, .failed, .skipped, .ok, .skipped])
        #expect(rows[1].detail == "Incorrect API key provided.")
        #expect(rows[2].detail == "no key")
        #expect(rows[4].detail == "model not downloaded")
        #expect(CredentialCheck.exitCode(rows) == 3)

        let text = CredentialCheck.table(rows, live: true)
        #expect(text.contains("openai    env         SPEECHKIT_OPENAI_API_KEY  \u{2022}\u{2022}\u{2022}\u{2022}4f2a  ok       1.2"))
        #expect(text.contains("aqua      none        SPEECHKIT_AQUA_API_KEY    -         skipped  -     no key"))
        #expect(text.hasPrefix("PROVIDER  SOURCE      ENV VAR                   KEY       STATUS   TIME  DETAIL\n"))
    }

    @Test("a provider with no key is never probed")
    func missingKeysAreNotProbed() async {
        let probed = Probed()
        let rows = await check().liveRows(for: CLIProvider.allCases) { provider, _ in
            await probed.record(provider)
            return CredentialCheck.ProbeResult(status: .ok, seconds: 0.1)
        }
        #expect(await probed.providers == Set([.openai, .grok, .apple, .voz]))
        #expect(rows.filter { $0.status == .skipped }.map(\.provider)
            == ["elevenlabs", "aqua", "cohere", "meta", "gemini", "fish-audio"])
    }

    @Test("every provider is probed once, even above the concurrency cap")
    func concurrencyCoversEveryProvider() async {
        let keys = Dictionary(uniqueKeysWithValues: CLIProvider.allCases
            .filter(\.requiresCredential)
            .map { ($0, "key-\($0.rawValue)-0000") })
        let subject = CredentialCheck(environment: [:], store: InMemoryKeychainStore(keys: keys))
        let probed = Probed()
        let rows = await subject.liveRows(for: CLIProvider.allCases) { provider, _ in
            await probed.record(provider)
            return CredentialCheck.ProbeResult(status: .ok, seconds: 0.1)
        }
        #expect(await probed.count == CLIProvider.allCases.count)
        #expect(rows.allSatisfy { $0.status == .ok })
        #expect(CredentialCheck.exitCode(rows) == 0)
    }

    @Test("the credential handed to the probe is the resolved one")
    func probeReceivesCredential() async {
        let seen = SeenCredentials()
        _ = await check().liveRows(for: [.openai, .grok, .apple]) { provider, credential in
            await seen.record(provider, credential)
            return CredentialCheck.ProbeResult(status: .ok, seconds: 0.1)
        }
        #expect(await seen.credentials["openai"] == .apiKey("sk-proj-00004f2a"))
        #expect(await seen.credentials["grok"] == .apiKey("xai-0000beef"))
        #expect(await seen.credentials["apple"] == nil)
    }

    // MARK: - Output shape

    @Test("detail is a single line, truncated in the table and whole in JSON")
    func detailTruncation() async throws {
        let long = "The server rejected the request because the API key is not valid for this endpoint"
        let probe = fakeProbe([
            .openai: CredentialCheck.ProbeResult(status: .failed, seconds: 2, detail: long + "\nsecond line")
        ])
        let rows = await check().liveRows(for: [.openai], probe: probe)

        #expect(rows[0].detail == long + " second line")
        let cell = CredentialCheck.truncate(rows[0].detail ?? "", to: CredentialCheck.detailWidth)
        #expect(cell.count == CredentialCheck.detailWidth)
        #expect(cell.hasSuffix("..."))
        #expect(CredentialCheck.table(rows, live: true).contains(cell))

        let json = try CredentialCheck.json(rows)
        #expect(json.contains(long))
    }

    @Test("no cell carries a newline, tab, or the raw key")
    func cellsAreSafeToSplit() async {
        let probe = fakeProbe([
            .openai: CredentialCheck.ProbeResult(status: .failed, seconds: 1, detail: "line one\n\tline two")
        ])
        let rows = await check().liveRows(for: CLIProvider.allCases, probe: probe)
        for row in rows {
            let cells = [row.provider, row.source.rawValue, row.environmentVariable, row.key, row.detail]
            for cell in cells.compactMap({ $0 }) {
                #expect(!cell.contains("\n"))
                #expect(!cell.contains("\t"))
            }
            // Only the detail is free text, so the fixed cells stay comma free.
            #expect(!row.provider.contains(","))
            #expect(row.environmentVariable?.contains(",") != true)
            #expect(row.key?.contains(",") != true)
        }
        #expect(rows[4].detail == "line one line two")
    }

    @Test("JSON carries every column, with the documented keys")
    func jsonShape() async throws {
        let probe = fakeProbe([.openai: CredentialCheck.ProbeResult(status: .ok, seconds: 1.5)])
        let rows = await check().liveRows(for: [.openai, .apple], probe: probe)
        let text = try CredentialCheck.json(rows)
        let objects = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]]
        let parsed = try #require(objects)

        #expect(parsed.count == 2)
        // `detail` is absent on an `ok` row, because there is nothing to say.
        #expect(Swift.Set(parsed[0].keys) == ["provider", "source", "envVar", "key", "status", "seconds"])
        #expect(Swift.Set(parsed[1].keys) == ["provider", "source", "status", "seconds"])
        #expect(parsed[0]["provider"] as? String == "openai")
        #expect(parsed[0]["source"] as? String == "env")
        #expect(parsed[0]["envVar"] as? String == "SPEECHKIT_OPENAI_API_KEY")
        #expect(parsed[0]["key"] as? String == "\u{2022}\u{2022}\u{2022}\u{2022}4f2a")
        #expect(parsed[0]["status"] as? String == "ok")
        #expect(parsed[0]["seconds"] as? Double == 1.5)
        #expect(parsed[1]["source"] as? String == "not needed")
        #expect(parsed[1]["envVar"] == nil)
    }

    @Test("the presence JSON omits the live columns")
    func presenceJSONOmitsLiveColumns() throws {
        let text = try CredentialCheck.json(check().rows(for: [.openai]))
        let objects = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]]
        let parsed = try #require(objects)
        #expect(Swift.Set(parsed[0].keys) == ["provider", "source", "envVar", "key"])
    }

    // MARK: - Probe audio

    @Test("the probe clip is a readable 16 kHz mono WAV")
    func probeClipIsGenerated() throws {
        try ProbeAudio.requireTools()
        let clip = try ProbeAudio.make()
        defer { clip.remove() }

        #expect(clip.url.pathExtension == "wav")
        let size = try FileManager.default.attributesOfItem(atPath: clip.url.path)[.size] as? Int ?? 0
        #expect(size > 1_000)

        clip.remove()
        #expect(!FileManager.default.fileExists(atPath: clip.directory.path))
    }

    // MARK: - Integration

    @Test(
        "--live checks apple on device",
        .enabled(if: CredentialCheckTests.appleIsAvailable)
    )
    func liveAppleOnly() async throws {
        try ProbeAudio.requireTools()
        let clip = try ProbeAudio.make()
        defer { clip.remove() }

        let rows = await CredentialCheck(environment: [:], store: nil).liveRows(
            for: [.apple],
            probe: CredentialCheck.liveProbe(clip: clip.url, console: Console(verbosity: .quiet))
        )
        #expect(rows.count == 1)
        #expect(rows[0].source == .notNeeded)
        #expect(rows[0].status == .ok, "apple reported \(rows[0].detail ?? "no detail")")
        #expect((rows[0].seconds ?? 0) > 0)
        #expect(CredentialCheck.exitCode(rows) == 0)
    }

    /// Whether Apple's local speech analyzer exists on this machine.
    static var appleIsAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}

/// Records which providers a fake probe saw.
private actor Probed {
    private(set) var providers: Set<CLIProvider> = []
    private(set) var count = 0

    func record(_ provider: CLIProvider) {
        providers.insert(provider)
        count += 1
    }
}

/// Records the credential a fake probe was handed for each provider.
private actor SeenCredentials {
    private(set) var credentials: [String: SpeechCredential] = [:]

    func record(_ provider: CLIProvider, _ credential: SpeechCredential?) {
        credentials[provider.rawValue] = credential
    }
}
