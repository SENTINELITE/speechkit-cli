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
