import Foundation
import SpeechKit
import Testing
@testable import SpeechKitCLICore

/// Mapping tests for the on-device runner.
///
/// `AppleSpeechFileTranscriptionResponse` is a plain value type, so the mapping
/// is exercised without the Speech framework and without audio.
@Suite("Apple mapping")
struct AppleRunnerTests {
    private let file = URL(fileURLWithPath: "/tmp/talk.wav")

    @available(macOS 26.0, *)
    private func entry(
        _ text: String,
        start: Double?,
        duration: Double?,
        words: [SpeechTranscriptWord] = []
    ) -> SpeechTranscriptEntry {
        SpeechTranscriptEntry(
            provider: .apple,
            text: text,
            start: start,
            duration: duration,
            speaker: "en_US",
            words: words
        )
    }

    @available(macOS 26.0, *)
    private func word(_ text: String, _ start: Double, _ end: Double, confidence: Double? = nil) -> SpeechTranscriptWord {
        SpeechTranscriptWord(text: text, start: start, end: end, speaker: "en_US", confidence: confidence)
    }

    @Test("Entries with words become words and cue-built segments")
    func entriesWithWords() {
        guard #available(macOS 26.0, *) else { return }
        let response = AppleSpeechFileTranscriptionResponse(
            locale: Locale(identifier: "en_US"),
            text: "Hello there. How are you?",
            entries: [
                entry("Hello there.", start: 0, duration: 0.95, words: [
                    word("Hello", 0, 0.42, confidence: 0.9),
                    word("there.", 0.42, 0.95),
                ]),
                entry("How are you?", start: 1.4, duration: 0.8, words: [
                    word("How", 1.4, 1.6),
                    word("are", 1.6, 1.8),
                    word("you?", 1.8, 2.2),
                ]),
            ]
        )
        let document = AppleRunner.map(response, file: file)

        #expect(document.provider == "apple")
        #expect(document.model == nil)
        #expect(document.words.count == 5)
        #expect(document.words[0] == TranscriptDocument.Word(
            text: "Hello",
            start: 0,
            end: 0.42,
            speaker: nil,
            confidence: 0.9
        ))
        // SpeechKit fills `speaker` with the locale, which is not a speaker.
        #expect(document.words.allSatisfy { $0.speaker == nil })
        // The entries are regrouped by the cue rules rather than kept as they
        // arrived: the pause here is too short to split the cue.
        #expect(document.segments.count == 1)
        #expect(document.segments[0].text == "Hello there. How are you?")
        #expect(document.segments.allSatisfy { $0.speaker == nil })
        #expect(document.duration == 2.2)
    }

    @Test("Entries without words stand as their own segments")
    func entriesWithoutWords() {
        guard #available(macOS 26.0, *) else { return }
        let response = AppleSpeechFileTranscriptionResponse(
            locale: Locale(identifier: "en_US"),
            text: "Hello there. How are you?",
            entries: [
                entry("Hello there.", start: 0, duration: 0.95),
                entry("  ", start: 1.0, duration: 0.1),
                entry("How are you?", start: 1.4, duration: 0.8),
            ]
        )
        let document = AppleRunner.map(response, file: file)

        #expect(document.words.isEmpty)
        #expect(document.segments == [
            TranscriptDocument.Segment(start: 0, end: 0.95, text: "Hello there."),
            TranscriptDocument.Segment(start: 1.4, end: 2.2000000000000002, text: "How are you?"),
        ])
        #expect(document.duration == 2.2000000000000002)
    }

    @Test("Entries out of order are sorted, and an impossible one is dropped")
    func entriesSorted() {
        guard #available(macOS 26.0, *) else { return }
        let response = AppleSpeechFileTranscriptionResponse(
            locale: Locale(identifier: "en_US"),
            text: "one two",
            entries: [
                entry("two", start: 1.4, duration: 0.5),
                entry("one", start: 0, duration: 0.5),
                entry("impossible", start: 3, duration: -1),
            ]
        )
        let document = AppleRunner.map(response, file: file)
        #expect(document.segments.map(\.text) == ["one", "two"])
    }

    @Test("The document language is the BCP-47 tag rather than the POSIX identifier")
    func bcp47Language() {
        guard #available(macOS 26.0, *) else { return }
        let response = AppleSpeechFileTranscriptionResponse(
            locale: Locale(identifier: "en_US"),
            text: "Hello",
            entries: [entry("Hello", start: 0, duration: 0.5)]
        )
        #expect(AppleRunner.map(response, file: file).language == "en-US")
    }

    @Test("Warnings passed in are carried into the document")
    func warningsCarried() {
        guard #available(macOS 26.0, *) else { return }
        let response = AppleSpeechFileTranscriptionResponse(
            locale: Locale(identifier: "fr_FR"),
            text: "Bonjour",
            entries: [entry("Bonjour", start: 0, duration: 0.5)]
        )
        let document = AppleRunner.map(
            response,
            file: file,
            warnings: ["Apple local transcription takes no prompt; --prompt is ignored."]
        )
        #expect(document.language == "fr-FR")
        #expect(document.warnings.count == 1)
    }

    @Test("A locale is supported when the tag matches, or when a bare language matches a region")
    func localeMatching() {
        guard #available(macOS 26.0, *) else { return }
        let supported = [Locale(identifier: "en_US"), Locale(identifier: "fr_FR")]
        #expect(AppleRunner.isSupported(Locale(identifier: "en-US"), in: supported))
        #expect(AppleRunner.isSupported(Locale(identifier: "en_US"), in: supported))
        #expect(AppleRunner.isSupported(Locale(identifier: "en"), in: supported))
        #expect(AppleRunner.isSupported(Locale(identifier: "de"), in: supported) == false)
        #expect(AppleRunner.isSupported(Locale(identifier: "en-GB"), in: supported) == false)
    }

    @Test("An unsupported --language is refused with the locales this machine has")
    func unsupportedLanguage() async {
        guard #available(macOS 26.0, *) else { return }
        let context = RunContext(languages: ["xx-YY"])
        do {
            _ = try await ProviderRegistry.makeRunner(for: .apple, context: context)
            Issue.record("expected a thrown error")
        } catch let error as CLIError {
            #expect(error.exitCode == 1)
            #expect(error.localizedDescription.contains("xx-YY"))
            #expect(error.localizedDescription.contains("speechkit languages apple"))
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("A supported --language passes validation")
    func supportedLanguage() async throws {
        guard #available(macOS 26.0, *) else { return }
        let context = RunContext(languages: ["en-US"])
        let runner = try await ProviderRegistry.makeRunner(for: .apple, context: context)
        #expect(runner is AppleRunner)
    }
}
