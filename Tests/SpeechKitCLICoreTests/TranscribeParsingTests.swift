import Foundation
import Testing
@testable import SpeechKitCLICore

@Suite("Argument parsing")
struct TranscribeParsingTests {
    @Test("The full phase one flag set parses")
    func fullFlagSet() throws {
        let command = try Transcribe.parse([
            "a.wav", "b.wav",
            "--provider", "OpenAI",
            "--language", "en", "--language", "fr",
            "--model", "gpt-transcribe",
            "--format", "txt", "--format", "json",
            "--output-dir", "/tmp/out",
            "--overwrite",
            "--api-key", "sk-test",
            "--endpoint", "https://proxy.example.com/v1/audio/transcriptions",
            "--timeout", "120",
            "--prompt", "a hint",
            "--keyword", "SpeechKit", "--keyword", "Swift",
            "--words",
            "--diarize",
            "--cues", "words",
            "--max-cue-duration", "5",
            "--max-cue-chars", "42",
            "--jobs", "3",
            "--raw",
            "--verbose",
        ])

        #expect(command.files == ["a.wav", "b.wav"])
        #expect(command.provider == .openai)
        #expect(command.transcription.language == ["en", "fr"])
        #expect(command.transcription.model == "gpt-transcribe")
        #expect(command.outputOptions.resolvedFormats == [.txt, .json])
        #expect(command.outputOptions.outputDir == "/tmp/out")
        #expect(command.outputOptions.overwrite)
        #expect(command.transcription.apiKey == "sk-test")
        #expect(command.transcription.timeout == 120)
        #expect(command.transcription.prompt == "a hint")
        #expect(command.transcription.keyword == ["SpeechKit", "Swift"])
        #expect(command.transcription.words)
        #expect(command.transcription.diarize)
        #expect(command.cues == .words)
        #expect(command.maxCueDuration == 5)
        #expect(command.maxCueChars == 42)
        #expect(command.jobs == 3)
        #expect(command.raw)
        #expect(command.globals.verbose)
    }

    @Test("Short flags parse")
    func shortFlags() throws {
        let command = try Transcribe.parse(["a.wav", "-p", "grok", "-l", "en", "-m", "grok-stt", "-f", "json", "-o", "/tmp", "-j", "4", "-q"])
        #expect(command.provider == .grok)
        #expect(command.outputOptions.resolvedFormats == [.json])
        #expect(command.jobs == 4)
        #expect(command.globals.quiet)
    }

    @Test("Defaults match the plan")
    func defaults() throws {
        let command = try Transcribe.parse(["a.wav"])
        #expect(command.outputOptions.resolvedFormats == [.txt])
        #expect(command.cues == .segments)
        #expect(command.maxCueDuration == 7)
        #expect(command.maxCueChars == 84)
        #expect(command.jobs == 2)
        #expect(command.provider == nil)
    }

    @Test("Subtitle formats are rejected in this phase")
    func subtitlesRejected() {
        #expect(throws: (any Error).self) {
            _ = try Transcribe.parse(["a.wav", "-p", "grok", "-f", "srt"])
        }
    }

    @Test("--output needs one file and one format")
    func outputConstraint() {
        #expect(throws: (any Error).self) {
            _ = try Transcribe.parse(["a.wav", "b.wav", "-p", "grok", "--output", "/tmp/a.txt"])
        }
        #expect(throws: (any Error).self) {
            _ = try Transcribe.parse(["a.wav", "-p", "grok", "-f", "txt", "-f", "json", "--stdout"])
        }
    }

    @Test("At least one file is required")
    func filesRequired() {
        #expect(throws: (any Error).self) {
            _ = try Transcribe.parse(["-p", "grok"])
        }
    }
}
