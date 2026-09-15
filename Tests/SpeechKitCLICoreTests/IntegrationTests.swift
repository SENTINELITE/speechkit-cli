import Foundation
import SpeechKitVoz
import Testing
@testable import SpeechKitCLICore

/// Live transcriptions against the real provider APIs.
///
/// Every cloud test here is disabled unless the matching credential is in the
/// environment, so a plain `swift test` skips them rather than failing on a
/// missing key or a network hop. Apple transcribes on device in about a second
/// and costs nothing, so it runs whenever the operating system supports it.
/// Audio is synthesised on the fly with `say` and `afconvert`, so the
/// repository carries no media fixtures.
@Suite("Integration", .serialized)
struct IntegrationTests {
    /// A 16 kHz mono WAV of spoken text, and the directory holding it.
    struct Sample {
        let url: URL
        let directory: URL

        func remove() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// The phrase every provider is asked to transcribe.
    static let phrase = "The quick brown fox jumps over the lazy dog."

    /// Returns `true` when the provider's API key is in the environment.
    static func hasKey(_ provider: CLIProvider) -> Bool {
        let name = CredentialResolver.environmentVariableName(for: provider)
        guard let value = ProcessInfo.processInfo.environment[name] else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Returns `true` when `SPEECHKIT_VOZ_INTEGRATION` asks for the VOZ test.
    static var wantsVozIntegration: Bool {
        ProcessInfo.processInfo.environment["SPEECHKIT_VOZ_INTEGRATION"] == "1"
    }

    /// Returns `true` when the VOZ model is already downloaded.
    ///
    /// This is the second half of the gate, checked in the test body rather
    /// than in a trait because building a `VozTranscriber` needs the main
    /// actor and a trait condition is evaluated from a `Sendable` closure. A
    /// test run must never trigger a 467 MB download, so an uncached model
    /// means the test does nothing.
    @MainActor
    static var hasCachedVozModel: Bool {
        VozTranscriber().isModelCached()
    }

    /// Returns `true` when this machine has Apple's local speech analyzer.
    static var hasAppleTranscriber: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// Speaks `phrase` into a 16 kHz mono WAV file.
    ///
    /// Meta accepts WAV alone, and every other provider accepts it too, so one
    /// encoding serves the whole suite.
    static func makeSample() throws -> Sample {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("speechkit-integration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let aiff = directory.appendingPathComponent("sample.aiff")
        let wav = directory.appendingPathComponent("sample.wav")
        try run("/usr/bin/say", ["-o", aiff.path, phrase])
        try run("/usr/bin/afconvert", ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", aiff.path, wav.path])
        return Sample(url: wav, directory: directory)
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw IntegrationError.toolFailed(tool, process.terminationStatus)
        }
    }

    enum IntegrationError: Error {
        case toolFailed(String, Int32)
    }

    /// Transcribes the sample with one provider and returns the document.
    static func transcribe(
        _ provider: CLIProvider,
        languages: [String] = [],
        wantsWords: Bool = false
    ) async throws -> TranscriptDocument {
        let sample = try makeSample()
        defer { sample.remove() }

        let resolver = CredentialResolver()
        let context = RunContext(
            credential: try resolver.resolve(provider: provider),
            languages: languages,
            wantsWords: wantsWords
        )
        let runner = try await ProviderRegistry.makeRunner(for: provider, context: context)
        return try await runner.transcribe(file: sample.url)
    }

    /// Checks that a live response carries usable text.
    static func expectTranscript(_ document: TranscriptDocument, provider: CLIProvider) {
        #expect(document.provider == provider.rawValue)
        #expect(!document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(document.text.lowercased().contains("fox"))
    }

    @Test("Grok transcribes a spoken sample", .enabled(if: IntegrationTests.hasKey(.grok)))
    func grok() async throws {
        Self.expectTranscript(try await Self.transcribe(.grok, languages: ["en"]), provider: .grok)
    }

    @Test("OpenAI transcribes a spoken sample", .enabled(if: IntegrationTests.hasKey(.openai)))
    func openAI() async throws {
        Self.expectTranscript(try await Self.transcribe(.openai, languages: ["en"]), provider: .openai)
    }

    @Test("Gemini transcribes a spoken sample", .enabled(if: IntegrationTests.hasKey(.gemini)))
    func gemini() async throws {
        Self.expectTranscript(try await Self.transcribe(.gemini, languages: ["en-US"]), provider: .gemini)
    }

    @Test("Meta transcribes a spoken sample", .enabled(if: IntegrationTests.hasKey(.meta)))
    func meta() async throws {
        Self.expectTranscript(try await Self.transcribe(.meta, languages: ["en"]), provider: .meta)
    }

    @Test("ElevenLabs transcribes a spoken sample", .enabled(if: IntegrationTests.hasKey(.elevenlabs)))
    func elevenLabs() async throws {
        Self.expectTranscript(try await Self.transcribe(.elevenlabs), provider: .elevenlabs)
    }

    @Test("Aqua transcribes a spoken sample", .enabled(if: IntegrationTests.hasKey(.aqua)))
    func aqua() async throws {
        Self.expectTranscript(try await Self.transcribe(.aqua, languages: ["en"]), provider: .aqua)
    }

    @Test("Cohere transcribes a spoken sample", .enabled(if: IntegrationTests.hasKey(.cohere)))
    func cohere() async throws {
        Self.expectTranscript(try await Self.transcribe(.cohere, languages: ["en"]), provider: .cohere)
    }

    @Test(
        "Apple transcribes a spoken sample on device",
        .enabled(if: IntegrationTests.hasAppleTranscriber)
    )
    func apple() async throws {
        guard #available(macOS 26.0, *) else { return }
        Self.expectTranscript(try await Self.transcribe(.apple, languages: ["en-US"]), provider: .apple)
    }

    @Test(
        "VOZ transcribes a spoken sample",
        .enabled(if: IntegrationTests.wantsVozIntegration)
    )
    func voz() async throws {
        guard await Self.hasCachedVozModel else { return }
        Self.expectTranscript(try await Self.transcribe(.voz), provider: .voz)
    }
    /// Speaks several phrases into a folder of WAVs, with matching references.
    ///
    /// - Returns: The audio directory, the reference directory holding one
    ///   `<stem>.txt` per file, and the parent to delete afterwards.
    static func makeBenchFolder() throws -> (audio: URL, references: URL, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("speechkit-bench-integration-\(UUID().uuidString)", isDirectory: true)
        let audio = root.appendingPathComponent("in", isDirectory: true)
        let references = root.appendingPathComponent("refs", isDirectory: true)
        try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: references, withIntermediateDirectories: true)

        let phrases = [
            "one": phrase,
            "two": "The rain in Spain stays mainly in the plain.",
        ]
        for (stem, spoken) in phrases {
            let aiff = root.appendingPathComponent("\(stem).aiff")
            try run("/usr/bin/say", ["-o", aiff.path, spoken])
            try run("/usr/bin/afconvert", [
                "-f", "WAVE", "-d", "LEI16@16000", "-c", "1",
                aiff.path, audio.appendingPathComponent("\(stem).wav").path,
            ])
            try spoken.write(
                to: references.appendingPathComponent("\(stem).txt"),
                atomically: true,
                encoding: .utf8
            )
        }
        return (audio, references, root)
    }

    @Test(
        "bench compares the on-device providers over a folder and scores them",
        .enabled(if: IntegrationTests.hasAppleTranscriber)
    )
    func bench() async throws {
        guard #available(macOS 26.0, *) else { return }
        let folder = try Self.makeBenchFolder()
        defer { try? FileManager.default.removeItem(at: folder.root) }
        let output = folder.root.appendingPathComponent("out", isDirectory: true)

        // VOZ joins the comparison only when its model is already on disk, so
        // a test run never triggers a 467 MB download.
        var providers = ["-p", "apple"]
        if Self.wantsVozIntegration, await Self.hasCachedVozModel {
            providers += ["-p", "voz"]
        }

        let command = try Bench.parse(
            [folder.audio.path] + providers + [
                "-o", output.path,
                "--reference-dir", folder.references.path,
                "--overwrite",
                "--quiet",
                // A test never writes to the machine's own usage history.
                "--no-history",
            ]
        )
        try await command.run()

        for name in ["summary.csv", "summary.md", "summary.json"] {
            #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent(name).path))
        }
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("one.apple.txt").path))

        let data = try Data(contentsOf: output.appendingPathComponent("summary.json"))
        let report = try JSONDecoder().decode(BenchReport.self, from: data)
        // Two files through each provider named in the pass.
        #expect(report.rows.count == 2 * (providers.count / 2))
        for row in report.rows {
            #expect(row.status == BenchRow.okStatus)
            #expect((row.wer ?? 1) < 0.5)
            #expect((row.wallSeconds ?? 0) > 0)
            #expect((row.chars ?? 0) > 0)
        }
    }
}
