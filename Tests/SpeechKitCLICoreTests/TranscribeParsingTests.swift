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
            "--output", "/tmp/out/",
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
            "--verbose",
        ])

        #expect(command.files == ["a.wav", "b.wav"])
        #expect(command.provider == .openai)
        #expect(command.transcription.language == ["en", "fr"])
        #expect(command.transcription.model == "gpt-transcribe")
        #expect(command.outputOptions.resolvedFormats == [.txt, .json])
        #expect(command.outputOptions.output == "/tmp/out/")
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

    @Test("Subtitle formats parse and keep their cue limits")
    func subtitleFormats() throws {
        let command = try Transcribe.parse([
            "a.wav", "-p", "grok", "-f", "srt", "-f", "vtt", "-o", "/tmp/out/",
            "--max-cue-duration", "4.5", "--max-cue-chars", "60",
        ])
        #expect(command.outputOptions.resolvedFormats == [.srt, .vtt])
        #expect(command.cueBuilder.maxCueDuration == 4.5)
        #expect(command.cueBuilder.maxCueChars == 60)
    }

    @Test("Cue limits must be positive")
    func cueLimitsValidated() {
        #expect(throws: (any Error).self) {
            _ = try Transcribe.parse(["a.wav", "-p", "grok", "-f", "srt", "--max-cue-duration", "0"])
        }
        #expect(throws: (any Error).self) {
            _ = try Transcribe.parse(["a.wav", "-p", "grok", "-f", "srt", "--max-cue-chars", "0"])
        }
    }

    @Test("--cues words replaces the segments with one cue per word")
    func cuesWords() throws {
        let command = try Transcribe.parse(["a.wav", "-p", "grok", "-f", "vtt", "--cues", "words"])
        let adjusted = try command.cueAdjusted(SubtitleSample.document)
        #expect(adjusted.segments.count == 8)
        #expect(adjusted.segments.map(\.text).first == "How")
    }

    @Test("--cues words leaves non-subtitle output alone")
    func cuesWordsIgnoredForText() throws {
        let command = try Transcribe.parse(["a.wav", "-p", "grok", "-f", "txt", "--cues", "words"])
        #expect(try command.cueAdjusted(SubtitleSample.document) == SubtitleSample.document)
    }

    @Test("--cues words needs word timings")
    func cuesWordsWithoutWords() throws {
        let command = try Transcribe.parse(["a.wav", "-p", "grok", "-f", "srt", "--cues", "words"])
        var document = SubtitleSample.document
        document.words = []
        #expect(throws: CLIError.self) {
            _ = try command.cueAdjusted(document)
        }
    }

    @Test("--cues segments leaves the provider segments in place")
    func cuesSegments() throws {
        let command = try Transcribe.parse(["a.wav", "-p", "grok", "-f", "srt"])
        #expect(try command.cueAdjusted(SubtitleSample.document) == SubtitleSample.document)
    }

    @Test("The run context carries the cue limits and mode")
    func runContextDefaults() {
        let defaults = RunContext()
        #expect(defaults.maxCueDuration == 7)
        #expect(defaults.maxCueChars == 84)
        #expect(defaults.cueMode == .segments)

        let context = RunContext(maxCueDuration: 4, maxCueChars: 50, cueMode: .words)
        #expect(context.cueBuilder.maxCueDuration == 4)
        #expect(context.cueBuilder.maxCueChars == 50)
    }

    @Test("--output needs one file and one format")
    func outputConstraint() {
        #expect(throws: (any Error).self) {
            _ = try Transcribe.parse(["a.wav", "b.wav", "-p", "grok", "--output", "/tmp/a.txt"])
        }
        #expect(throws: (any Error).self) {
            _ = try Transcribe.parse(["a.wav", "-p", "grok", "-f", "txt", "-f", "json", "--output", "/tmp/a.txt"])
        }
    }

    @Test("At least one file is required")
    func filesRequired() {
        #expect(throws: (any Error).self) {
            _ = try Transcribe.parse(["-p", "grok"])
        }
    }
}
