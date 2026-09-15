import Foundation
import Testing
@testable import SpeechKitCLICore

@Suite("Pre-upload validation")
struct PreUploadValidationTests {
    /// Creates a temporary directory that is removed when the test finishes.
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("speechkit-validation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ bytes: Int, named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    @Test("A missing file is rejected before any upload")
    func missingFile() throws {
        let command = try Transcribe.parse(["/tmp/does-not-exist-\(UUID().uuidString).wav", "-p", "openai"])
        let error = #expect(throws: CLIError.self) {
            _ = try command.validate(provider: .openai, capabilities: .capabilities(for: .openai))
        }
        #expect(error?.exitCode == 1)
        if case .fileNotFound = error { } else { Issue.record("expected fileNotFound, got \(String(describing: error))") }
    }

    @Test("A directory is rejected with a hint to use a glob")
    func directoryRejected() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let command = try Transcribe.parse([directory.path, "-p", "openai"])
        let error = #expect(throws: CLIError.self) {
            _ = try command.validate(provider: .openai, capabilities: .capabilities(for: .openai))
        }
        #expect(error == .inputIsDirectory(URL(fileURLWithPath: directory.path)))
        #expect(error?.localizedDescription.contains("shell glob") == true)
    }

    @Test("An extension the provider does not accept is rejected")
    func badExtension() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try write(16, named: "clip.aiff", in: directory)

        let command = try Transcribe.parse([file.path, "-p", "meta"])
        let error = #expect(throws: CLIError.self) {
            _ = try command.validate(provider: .meta, capabilities: .capabilities(for: .meta))
        }
        #expect(error?.exitCode == 1)
        #expect(error?.localizedDescription.contains(".wav") == true)
    }

    @Test("A provider with no extension list accepts anything")
    func noExtensionList() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try write(16, named: "clip.caf", in: directory)

        let command = try Transcribe.parse([file.path, "-p", "elevenlabs"])
        let inputs = try command.validate(provider: .elevenlabs, capabilities: .capabilities(for: .elevenlabs))
        #expect(inputs == [file])
    }

    @Test("A file over the provider limit is rejected before any upload")
    func oversizeFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try write(4096, named: "clip.wav", in: directory)

        let real = ProviderCapabilities.capabilities(for: .openai)
        let tiny = ProviderCapabilities(
            defaultFileModel: real.defaultFileModel,
            supportsWordTimestamps: real.supportsWordTimestamps,
            supportsSegments: real.supportsSegments,
            supportsDiarization: real.supportsDiarization,
            languageStyle: real.languageStyle,
            maxFileBytes: 1024,
            acceptedExtensions: real.acceptedExtensions
        )

        let command = try Transcribe.parse([file.path, "-p", "openai"])
        #expect(throws: CLIError.fileTooLarge(file, limit: 1024)) {
            _ = try command.validate(provider: .openai, capabilities: tiny)
        }
        #expect(try command.validate(provider: .openai, capabilities: real) == [file])
    }

    @Test("srt on a text-only provider fails before the upload, not after")
    func subtitlesOnTextOnlyProvider() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try write(16, named: "clip.wav", in: directory)

        for provider in [CLIProvider.cohere, .aqua] {
            let command = try Transcribe.parse([file.path, "-p", provider.rawValue, "-f", "srt", "-f", "vtt"])
            let error = #expect(throws: CLIError.self) {
                _ = try command.validate(provider: provider, capabilities: .capabilities(for: provider))
            }
            #expect(error == .subtitlesUnsupported(provider: provider, formats: ["srt", "vtt"]))
            #expect(error?.exitCode == 1)
            #expect(error?.localizedDescription.contains("--format txt or json") == true)
        }
    }

    @Test("Text and JSON still work on a text-only provider")
    func textFormatsAllowed() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try write(16, named: "clip.wav", in: directory)

        let command = try Transcribe.parse([file.path, "-p", "cohere", "-f", "json"])
        #expect(try command.validate(provider: .cohere, capabilities: .capabilities(for: .cohere)) == [file])
    }

    @Test("--words and --diarize are still gated by the capability table")
    func capabilityGating() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try write(16, named: "clip.wav", in: directory)

        let words = try Transcribe.parse([file.path, "-p", "meta", "--words"])
        #expect(throws: CLIError.unsupportedCapability(provider: .meta, capability: "word timestamps")) {
            _ = try words.validate(provider: .meta, capabilities: .capabilities(for: .meta))
        }

        let diarize = try Transcribe.parse([file.path, "-p", "aqua", "--diarize"])
        #expect(throws: CLIError.unsupportedCapability(provider: .aqua, capability: "speaker labels")) {
            _ = try diarize.validate(provider: .aqua, capabilities: .capabilities(for: .aqua))
        }
    }

    @Test("Two inputs with the same stem are refused before any upload")
    func stemCollision() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try write(16, named: "talk.wav", in: directory)
        let second = try write(16, named: "talk.mp3", in: directory)

        let command = try Transcribe.parse([first.path, second.path, "-p", "openai"])
        let error = #expect(throws: CLIError.self) {
            _ = try command.validate(provider: .openai, capabilities: .capabilities(for: .openai))
        }
        #expect(error?.exitCode == 1)
        #expect(error?.localizedDescription.contains(first.path) == true)
        #expect(error?.localizedDescription.contains(second.path) == true)
        #expect(error?.localizedDescription.contains("talk.txt") == true)
    }

    @Test("Different directories collide once --output-dir gathers them")
    func stemCollisionAcrossDirectories() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let left = directory.appendingPathComponent("left", isDirectory: true)
        let right = directory.appendingPathComponent("right", isDirectory: true)
        try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)
        let first = try write(16, named: "talk.wav", in: left)
        let second = try write(16, named: "talk.wav", in: right)

        let apart = try Transcribe.parse([first.path, second.path, "-p", "openai"])
        #expect(try apart.validate(provider: .openai, capabilities: .capabilities(for: .openai)).count == 2)

        let together = try Transcribe.parse([
            first.path, second.path, "-p", "openai", "-o", directory.appendingPathComponent("out").path,
        ])
        #expect(throws: CLIError.self) {
            _ = try together.validate(provider: .openai, capabilities: .capabilities(for: .openai))
        }
    }

    @Test("--output-dir cannot be combined with --output or --stdout")
    func outputDirExclusivity() {
        #expect(throws: (any Error).self) {
            _ = try Transcribe.parse(["a.wav", "-p", "grok", "-o", "/tmp/out", "--output", "/tmp/a.txt"])
        }
        #expect(throws: (any Error).self) {
            _ = try Transcribe.parse(["a.wav", "-p", "grok", "-o", "/tmp/out", "--stdout"])
        }
    }

    @Test("A skipped destination is spelled out rather than read as a write")
    func skippedDestinationReported() {
        let url = URL(fileURLWithPath: "/tmp/out/talk.txt")
        let subtitle = URL(fileURLWithPath: "/tmp/out/talk.srt")

        #expect(Transcribe.progressTarget(for: [.file(url)]) == "talk.txt")
        #expect(Transcribe.progressTarget(for: [.skipped(url)]) == "talk.txt (exists, skipped)")
        #expect(
            Transcribe.progressTarget(for: [.file(subtitle), .skipped(url)])
                == "talk.srt, talk.txt (exists, skipped)"
        )
        #expect(Transcribe.progressTarget(for: [.standardOutput]) == "stdout")
    }

    @Test("A subtitle format asks for word timings from the providers that need them")
    func subtitlesRequestWords() {
        for provider in [CLIProvider.grok, .gemini, .openai, .elevenlabs] {
            #expect(Transcribe.wantsWords(requested: false, formats: [.srt], provider: provider))
            #expect(Transcribe.wantsWords(requested: false, formats: [.txt, .vtt], provider: provider))
            #expect(Transcribe.wantsWords(requested: false, formats: [.txt], provider: provider) == false)
        }
        for provider in [CLIProvider.meta, .apple] {
            #expect(Transcribe.wantsWords(requested: false, formats: [.srt], provider: provider) == false)
            #expect(Transcribe.wantsWords(requested: true, formats: [.txt], provider: provider))
        }
    }

    @Test("A bare word that is not a file reads as a mistyped subcommand")
    func subcommandHint() throws {
        let hint = try #require(Transcribe.subcommandHint(for: ["bogus"]))
        #expect(hint.contains("'bogus' is not a file"))
        #expect(hint.contains("speechkit --help"))

        #expect(Transcribe.subcommandHint(for: ["missing.wav"]) == nil)
        #expect(Transcribe.subcommandHint(for: ["./bogus"]) == nil)
        #expect(Transcribe.subcommandHint(for: ["/tmp/bogus"]) == nil)
    }

    @Test("Inputs keep the order they were named in")
    func inputOrder() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try write(16, named: "b.wav", in: directory)
        let second = try write(16, named: "a.wav", in: directory)

        let command = try Transcribe.parse([first.path, second.path, "-p", "openai"])
        #expect(try command.validate(provider: .openai, capabilities: .capabilities(for: .openai)) == [first, second])
    }
}
