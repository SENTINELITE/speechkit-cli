import Foundation
import Testing
@testable import SpeechKitCLICore

/// Loads the golden `.srt` and `.vtt` files next to the JSON fixtures.
enum SubtitleFixture {
    static func text(_ name: String, extension fileExtension: String) throws -> String {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "Fixtures"
        ) else {
            throw Fixture.FixtureError.missing("\(name).\(fileExtension)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

/// The two-speaker document both subtitle suites render.
enum SubtitleSample {
    static var document: TranscriptDocument {
        TranscriptDocument(
            provider: "grok",
            model: "grok-stt",
            sourceFile: "/tmp/talk.wav",
            text: "How is the weather? It is sunny today.",
            language: "en",
            duration: 7.25,
            segments: [
                TranscriptDocument.Segment(start: 1.52, end: 4.64, text: "How is the weather?", speaker: "0"),
                TranscriptDocument.Segment(start: 5, end: 7.25, text: "It is sunny today.", speaker: "1"),
            ],
            words: [
                TranscriptDocument.Word(text: "How", start: 1.52, end: 1.9, speaker: "0"),
                TranscriptDocument.Word(text: "is", start: 1.9, end: 2.1, speaker: "0"),
                TranscriptDocument.Word(text: "the", start: 2.1, end: 2.4, speaker: "0"),
                TranscriptDocument.Word(text: "weather?", start: 2.4, end: 4.64, speaker: "0"),
                TranscriptDocument.Word(text: "It", start: 5, end: 5.2, speaker: "1"),
                TranscriptDocument.Word(text: "is", start: 5.2, end: 5.4, speaker: "1"),
                TranscriptDocument.Word(text: "sunny", start: 5.4, end: 6, speaker: "1"),
                TranscriptDocument.Word(text: "today.", start: 6, end: 7.25, speaker: "1"),
            ]
        )
    }

    /// A document whose only segment carries no timings, as Aqua and Cohere produce.
    static var untimed: TranscriptDocument {
        TranscriptDocument(
            provider: "cohere",
            sourceFile: "/tmp/talk.wav",
            text: "Hello there.",
            segments: [TranscriptDocument.Segment(start: 0, end: 0, text: "Hello there.")]
        )
    }
}

@Suite("SubRip output")
struct SRTFormatterTests {
    @Test("Cues are numbered and separated by a blank line")
    func basic() throws {
        let rendered = try SRTFormatter().render(SubtitleSample.document)
        #expect(rendered == (try SubtitleFixture.text("srt-basic", extension: "srt")))
    }

    @Test("Speaker prefixes appear only when asked for")
    func speakers() throws {
        let rendered = try SRTFormatter(showSpeakers: true).render(SubtitleSample.document)
        #expect(rendered == (try SubtitleFixture.text("srt-speakers", extension: "srt")))
    }

    @Test("Hours run past 99 and a zero length cue still lasts a millisecond")
    func longHours() throws {
        let document = TranscriptDocument(
            provider: "grok",
            sourceFile: "/tmp/long.wav",
            text: "",
            segments: [
                TranscriptDocument.Segment(start: 360_000, end: 360_002.5, text: "Still talking after a hundred hours."),
                TranscriptDocument.Segment(start: 363_661.001, end: 363_661.001, text: "A zero length cue still plays."),
            ]
        )
        #expect(try SRTFormatter().render(document) == (try SubtitleFixture.text("srt-long-hours", extension: "srt")))
    }

    @Test("Long cue text wraps onto two lines")
    func wrapping() throws {
        let document = TranscriptDocument(
            provider: "grok",
            sourceFile: "/tmp/long.wav",
            text: "",
            segments: [
                TranscriptDocument.Segment(
                    start: 0,
                    end: 6,
                    text: "The quick brown fox jumps over the lazy dog and keeps on running down the road"
                )
            ]
        )
        #expect(try SRTFormatter().render(document) == (try SubtitleFixture.text("srt-wrapped", extension: "srt")))
    }

    @Test("Output is UTF-8 with LF line endings and no byte order mark")
    func encoding() throws {
        let rendered = try SRTFormatter().render(SubtitleSample.document)
        #expect(!rendered.contains("\r"))
        #expect(rendered.hasSuffix("\n"))
        let data = Data(rendered.utf8)
        #expect(data.prefix(3) != Data([0xEF, 0xBB, 0xBF]))
    }

    @Test("A transcript with no timings is refused with the documented message")
    func noTimingData() {
        #expect(throws: CLIError.noTimingData(provider: "cohere")) {
            _ = try SRTFormatter().render(SubtitleSample.untimed)
        }
        #expect(throws: CLIError.noTimingData(provider: "aqua")) {
            _ = try SRTFormatter().render(
                TranscriptDocument(provider: "aqua", sourceFile: "/tmp/a.wav", text: "Hello")
            )
        }
        let message = CLIError.noTimingData(provider: "cohere").localizedDescription
        #expect(message == "no timing data from cohere; use --format txt or json, or pick a provider from 'speechkit providers' with segments")
    }
}
