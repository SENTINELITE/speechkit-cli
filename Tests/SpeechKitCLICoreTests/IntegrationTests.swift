import Foundation
import Testing
@testable import SpeechKitCLICore

/// Live transcriptions against the real provider APIs.
///
/// Every test here is disabled unless the matching credential is in the
/// environment, so a plain `swift test` skips the whole suite rather than
/// failing on a missing key or a network hop. Audio is synthesised on the fly
/// with `say` and `afconvert`, so the repository carries no media fixtures.
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

    /// Returns `true` when the on-device test was asked for explicitly.
    static var wantsLocalIntegration: Bool {
        ProcessInfo.processInfo.environment["SPEECHKIT_INTEGRATION"] == "1"
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
        let runner = try ProviderRegistry.makeRunner(for: provider, context: context)
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
        .enabled(if: IntegrationTests.wantsLocalIntegration)
    )
    func apple() async throws {
        guard #available(macOS 26.0, *) else { return }
        Self.expectTranscript(try await Self.transcribe(.apple, languages: ["en-US"]), provider: .apple)
    }
}
