import Foundation
import Testing
@testable import SpeechKitCLICore

@Suite("Formatters")
struct FormatterTests {
    private var document: TranscriptDocument {
        TranscriptDocument(
            provider: "grok",
            model: "grok-stt",
            sourceFile: "/tmp/talk.wav",
            text: "Hello there. How are you?",
            language: "en",
            duration: 3.25,
            segments: [
                TranscriptDocument.Segment(start: 0, end: 0.95, text: "Hello there.", speaker: "0"),
                TranscriptDocument.Segment(start: 1.4, end: 2.2, text: "How are you?", speaker: "1")
            ],
            words: [
                TranscriptDocument.Word(text: "Hello", start: 0, end: 0.42, speaker: "0")
            ],
            warnings: ["a warning"]
        )
    }

    @Test("JSON output is pretty printed with sorted keys")
    func jsonGolden() throws {
        let rendered = try JSONFormatter().render(document)
        let expected = """
        {
          "duration" : 3.25,
          "language" : "en",
          "model" : "grok-stt",
          "provider" : "grok",
          "segments" : [
            {
              "end" : 0.95,
              "speaker" : "0",
              "start" : 0,
              "text" : "Hello there."
            },
            {
              "end" : 2.2,
              "speaker" : "1",
              "start" : 1.4,
              "text" : "How are you?"
            }
          ],
          "sourceFile" : "/tmp/talk.wav",
          "text" : "Hello there. How are you?",
          "warnings" : [
            "a warning"
          ],
          "words" : [
            {
              "end" : 0.42,
              "speaker" : "0",
              "start" : 0,
              "text" : "Hello"
            }
          ]
        }

        """
        #expect(rendered == expected)
    }

    @Test("JSON round-trips back into a document")
    func jsonRoundTrip() throws {
        let rendered = try JSONFormatter().render(document)
        let decoded = try JSONDecoder().decode(TranscriptDocument.self, from: Data(rendered.utf8))
        #expect(decoded == document)
    }

    @Test("Plain text is the transcript plus a newline")
    func plainText() throws {
        let rendered = try PlainTextFormatter().render(document)
        #expect(rendered == "Hello there. How are you?\n")
    }

    @Test("Plain text with speaker labels writes one paragraph per turn")
    func plainTextDiarized() throws {
        let rendered = try PlainTextFormatter(includesSpeakerLabels: true).render(document)
        #expect(rendered == "A: Hello there.\n\nB: How are you?\n")
    }

    @Test("Speaker labels run past Z")
    func speakerLabels() {
        #expect(SpeakerLabels.label(at: 0) == "A")
        #expect(SpeakerLabels.label(at: 25) == "Z")
        #expect(SpeakerLabels.label(at: 26) == "AA")
    }

    @Test("Registry returns a formatter for every format")
    func registry() throws {
        #expect(try FormatterRegistry.makeFormatter(for: .txt).fileExtension == "txt")
        #expect(try FormatterRegistry.makeFormatter(for: .json).fileExtension == "json")
        #expect(try FormatterRegistry.makeFormatter(for: .srt).fileExtension == "srt")
        #expect(try FormatterRegistry.makeFormatter(for: .vtt).fileExtension == "vtt")
    }

    @Test("Registry threads the speaker, word timing, and cue limit options through")
    func registryOptions() throws {
        let builder = CueBuilder(maxCueDuration: 3, maxCueChars: 30, maxLineChars: 15)
        let srt = try #require(
            try FormatterRegistry.makeFormatter(
                for: .srt,
                includesSpeakerLabels: true,
                cueBuilder: builder
            ) as? SRTFormatter
        )
        #expect(srt.showSpeakers)
        #expect(srt.cueBuilder.maxLineChars == 15)

        let vtt = try #require(
            try FormatterRegistry.makeFormatter(
                for: .vtt,
                includesSpeakerLabels: false,
                includesWordTimings: true
            ) as? VTTFormatter
        )
        #expect(vtt.showWordTimings)
        #expect(vtt.showSpeakers == false)
    }
}
