import Foundation
import Testing
@testable import SpeechKitCLICore

@Suite("WebVTT output")
struct VTTFormatterTests {
    @Test("The header, note block, and cues match the golden file")
    func basic() throws {
        let rendered = try VTTFormatter().render(SubtitleSample.document)
        #expect(rendered == (try SubtitleFixture.text("vtt-basic", extension: "vtt")))
    }

    @Test("Speakers become voice spans")
    func speakers() throws {
        let rendered = try VTTFormatter(showSpeakers: true).render(SubtitleSample.document)
        #expect(rendered == (try SubtitleFixture.text("vtt-speakers", extension: "vtt")))
    }

    @Test("Word timings become inline tags, and the first word of a cue has none")
    func inlineWordTags() throws {
        let rendered = try VTTFormatter(showWordTimings: true).render(SubtitleSample.document)
        #expect(rendered == (try SubtitleFixture.text("vtt-words", extension: "vtt")))
    }

    @Test("One cue per word carries no inline tags")
    func cuePerWord() throws {
        var document = SubtitleSample.document
        document.segments = CueBuilder().wordCues(from: document.words)
        let rendered = try VTTFormatter(showWordTimings: true).render(document)
        #expect(rendered == (try SubtitleFixture.text("vtt-cue-per-word", extension: "vtt")))
    }

    @Test("The note block leaves out a missing model and language")
    func sparseNote() throws {
        let document = TranscriptDocument(
            provider: "apple",
            sourceFile: "/tmp/a.wav",
            text: "Hello",
            segments: [TranscriptDocument.Segment(start: 0, end: 1, text: "Hello")]
        )
        let rendered = try VTTFormatter().render(document)
        #expect(rendered == "WEBVTT\n\nNOTE\nprovider: apple\n\n00:00:00.000 --> 00:00:01.000\nHello\n")
    }

    @Test("Word timings fall back to plain text when the cue has no words of its own")
    func wordTagFallback() throws {
        var document = SubtitleSample.document
        document.words = [TranscriptDocument.Word(text: "How", start: 1.52, end: 1.9)]
        let rendered = try VTTFormatter(showWordTimings: true).render(document)
        #expect(rendered == (try SubtitleFixture.text("vtt-basic", extension: "vtt")))
    }

    @Test("A transcript with no timings is refused with the documented message")
    func noTimingData() {
        #expect(throws: CLIError.noTimingData(provider: "cohere")) {
            _ = try VTTFormatter().render(SubtitleSample.untimed)
        }
    }

    @Test("Ampersands and angle brackets in cue text are escaped")
    func escapesCueText() throws {
        var document = SubtitleSample.document
        document.words = []
        document.segments = [
            TranscriptDocument.Segment(start: 0, end: 1, text: "AT&T called", speaker: "0"),
            TranscriptDocument.Segment(start: 1, end: 2, text: "<inaudible> then silence", speaker: "1"),
        ]
        let rendered = try VTTFormatter(showSpeakers: true).render(document)

        #expect(rendered.contains("AT&amp;T called"))
        #expect(rendered.contains("&lt;inaudible&gt; then silence"))
        #expect(rendered.contains("<v A>AT&amp;T called"))
        // The voice span is still markup rather than escaped text.
        #expect(rendered.contains("&lt;v ") == false)
    }

    @Test("Inline word timing tags escape the word text but not the tag")
    func escapesTaggedWords() throws {
        let document = TranscriptDocument(
            provider: "grok",
            sourceFile: "/tmp/a.wav",
            text: "AT&T <inaudible> today",
            segments: [TranscriptDocument.Segment(start: 0, end: 3, text: "AT&T <inaudible> today")],
            words: [
                TranscriptDocument.Word(text: "AT&T", start: 0, end: 1),
                TranscriptDocument.Word(text: "<inaudible>", start: 1, end: 2),
                TranscriptDocument.Word(text: "today", start: 2, end: 3),
            ]
        )
        let rendered = try VTTFormatter(showWordTimings: true).render(document)

        #expect(rendered.contains("AT&amp;T <00:00:01.000>&lt;inaudible&gt; <00:00:02.000>today"))
    }

    @Test("A NOTE value loses its line breaks and cue arrows")
    func sanitizesNote() throws {
        let document = TranscriptDocument(
            provider: "grok",
            model: "evil\nmodel",
            sourceFile: "/tmp/a.wav",
            text: "Hello",
            language: "en --> 00:00:05.000",
            segments: [TranscriptDocument.Segment(start: 0, end: 1, text: "Hello")]
        )
        let rendered = try VTTFormatter().render(document)
        let note = rendered.components(separatedBy: "\n\n")[1]

        #expect(note == "NOTE\nprovider: grok\nmodel: evil model\nlanguage: en -- 00:00:05.000")
        #expect(note.components(separatedBy: "\n").count == 4)
    }

    @Test("Output is UTF-8 with LF line endings")
    func encoding() throws {
        let rendered = try VTTFormatter(showSpeakers: true, showWordTimings: true).render(SubtitleSample.document)
        #expect(!rendered.contains("\r"))
        #expect(rendered.hasPrefix("WEBVTT\n"))
    }
}
