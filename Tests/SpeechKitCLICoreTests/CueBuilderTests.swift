import Foundation
import Testing
@testable import SpeechKitCLICore

@Suite("Cue builder")
struct CueBuilderTests {
    private func word(
        _ text: String,
        _ start: Double?,
        _ end: Double?,
        speaker: String? = nil
    ) -> TranscriptDocument.Word {
        TranscriptDocument.Word(text: text, start: start, end: end, speaker: speaker)
    }

    private func build(_ words: [TranscriptDocument.Word], _ builder: CueBuilder = CueBuilder()) -> [TranscriptDocument.Segment] {
        builder.segments(from: words, fallbackText: "", duration: nil)
    }

    @Test("A gap longer than the threshold starts a new cue")
    func gapSplit() {
        let cues = build([
            word("one", 0, 0.4),
            word("two", 0.4, 0.8),
            word("three", 1.7, 2.0),
        ])
        #expect(cues.map(\.text) == ["one two", "three"])
        #expect(cues[0].start == 0)
        #expect(cues[0].end == 0.8)
        #expect(cues[1].start == 1.7)
    }

    @Test("A gap at the threshold stays in the same cue")
    func gapAtThreshold() {
        let cues = build([
            word("one", 0, 0.4),
            word("two", 1.2, 1.5),
        ])
        #expect(cues.map(\.text) == ["one two"])
    }

    @Test("Sentence punctuation splits a cue that is already long enough")
    func sentenceSplit() {
        let cues = build([
            word("this", 0, 0.5),
            word("is", 0.5, 1.0),
            word("long.", 1.0, 1.8),
            word("Next", 1.9, 2.2),
        ])
        #expect(cues.map(\.text) == ["this is long.", "Next"])
    }

    @Test("Sentence punctuation leaves a short cue alone")
    func sentenceKeepsShortCue() {
        let cues = build([
            word("hi.", 0, 0.4),
            word("Next", 0.5, 0.9),
        ])
        #expect(cues.map(\.text) == ["hi. Next"])
    }

    @Test("Punctuation followed by a closing quote still ends a sentence")
    func sentenceWithClosingQuote() {
        let cues = build([
            word("he", 0, 0.5),
            word("said", 0.5, 1.0),
            word("\"yes.\"", 1.0, 1.9),
            word("Then", 2.0, 2.3),
        ])
        #expect(cues.map(\.text) == ["he said \"yes.\"", "Then"])
    }

    @Test("A speaker change starts a new cue")
    func speakerSplit() {
        let cues = build([
            word("hello", 0, 0.4, speaker: "0"),
            word("there", 0.4, 0.8, speaker: "0"),
            word("hi", 0.8, 1.1, speaker: "1"),
        ])
        #expect(cues.map(\.text) == ["hello there", "hi"])
        #expect(cues.map(\.speaker) == ["0", "1"])
    }

    @Test("A cue never runs past the character limit")
    func characterLimit() {
        let builder = CueBuilder(maxCueChars: 10)
        let cues = builder.segments(
            from: [word("abcd", 0, 0.2), word("efgh", 0.2, 0.4), word("ijkl", 0.4, 0.6)],
            fallbackText: "",
            duration: nil
        )
        #expect(cues.map(\.text) == ["abcd efgh", "ijkl"])
    }

    @Test("A cue never runs past the duration limit")
    func durationLimit() {
        let builder = CueBuilder(maxCueDuration: 1.0)
        let cues = builder.segments(
            from: [word("a", 0, 0.4), word("b", 0.5, 0.9), word("c", 1.0, 1.4)],
            fallbackText: "",
            duration: nil
        )
        #expect(cues.map(\.text) == ["a b", "c"])
    }

    @Test("Unsorted words are put back in start order before splitting")
    func unsortedInput() {
        let cues = build([
            word("three", 1.7, 2.0),
            word("one", 0, 0.4),
            word("two", 0.4, 0.8),
        ])
        #expect(cues.map(\.text) == ["one two", "three"])
    }

    @Test("A missing end time gives the cue a one second tail")
    func missingEnd() {
        let cues = build([word("solo", 2.0, nil)])
        #expect(cues.count == 1)
        #expect(cues[0].start == 2.0)
        #expect(cues[0].end == 3.0)
    }

    @Test("A word with no start inherits the previous word's end")
    func missingStart() {
        let cues = build([
            word("one", 0, 0.4),
            word("two", nil, 0.9),
        ])
        #expect(cues.map(\.text) == ["one two"])
        #expect(cues[0].end == 0.9)
    }

    @Test("Zero length words stay in one cue and keep their times")
    func zeroLengthWords() {
        let cues = build([
            word("a", 1.0, 1.0),
            word("b", 1.0, 1.0),
        ])
        #expect(cues.count == 1)
        #expect(cues[0].start == 1.0)
        #expect(cues[0].end == 1.0)
        #expect(cues[0].text == "a b")
    }

    @Test("Empty words fall back to one untimed segment")
    func fallbackSegment() {
        let builder = CueBuilder()
        let cues = builder.segments(from: [], fallbackText: "  Hello there.  ", duration: 2)
        #expect(cues == [TranscriptDocument.Segment(start: 0, end: 2, text: "Hello there.")])
        #expect(builder.segments(from: [], fallbackText: "   ", duration: 2).isEmpty)
    }

    @Test("Blank word text is dropped")
    func blankWords() {
        let cues = build([word("  ", 0, 0.1), word("hi", 0.1, 0.4)])
        #expect(cues.map(\.text) == ["hi"])
    }

    @Test("Short text wraps onto one line")
    func wrapSingleLine() {
        #expect(CueBuilder().wrapLines("How is the weather?") == ["How is the weather?"])
        #expect(CueBuilder().wrapLines("   ").isEmpty)
    }

    @Test("Long text wraps onto two lines at word boundaries")
    func wrapTwoLines() {
        let builder = CueBuilder()
        let lines = builder.wrapLines("The quick brown fox jumps over the lazy dog and keeps running")
        #expect(lines.count == 2)
        #expect(lines[0] == "The quick brown fox jumps over the lazy")
        #expect(lines[0].count <= builder.maxLineChars)
        #expect(lines[1] == "dog and keeps running")
    }

    @Test("Text too long for two lines keeps every word on a longer second line")
    func wrapOverflow() {
        let builder = CueBuilder(maxLineChars: 10)
        let lines = builder.wrapLines("alpha beta gamma delta epsilon")
        #expect(lines == ["alpha beta", "gamma delta epsilon"])
    }

    @Test("A single word longer than the line width is never broken")
    func wrapUnbreakableWord() {
        let builder = CueBuilder(maxLineChars: 5)
        #expect(builder.wrapLines("supercalifragilistic") == ["supercalifragilistic"])
    }

    @Test("Word cues put one word in each cue")
    func wordCues() {
        let cues = CueBuilder().wordCues(from: [
            word("How", 1.52, 1.9, speaker: "0"),
            word("is", 1.9, nil, speaker: "0"),
            word("  ", 2.0, 2.1),
        ])
        #expect(cues.count == 2)
        #expect(cues[0] == TranscriptDocument.Segment(start: 1.52, end: 1.9, text: "How", speaker: "0"))
        #expect(cues[1].end == 2.9)
    }

    @Test("Word cues sort unsorted input")
    func wordCuesUnsorted() {
        let cues = CueBuilder().wordCues(from: [word("b", 1.0, 1.2), word("a", 0.1, 0.3)])
        #expect(cues.map(\.text) == ["a", "b"])
    }

    @Test("The sentence segmenter still delegates to the default cue rules")
    func segmenterDelegates() {
        let words = [word("one", 0, 0.4), word("two", 1.7, 2.0)]
        let viaSegmenter = SentenceSegmenter.segments(from: words, fallbackText: "one two", duration: 2)
        #expect(viaSegmenter == CueBuilder().segments(from: words, fallbackText: "one two", duration: 2))
        #expect(viaSegmenter.count == 2)
    }
}
