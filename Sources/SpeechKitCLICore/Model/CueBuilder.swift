import Foundation

/// Turns word timings into subtitle cues.
///
/// Providers that return words but no segments (Grok, Gemini, ElevenLabs, and
/// Apple when its entries run long) go through this type. A new cue starts when
/// any of these holds:
///
/// - the gap to the previous word is longer than ``gapThreshold``
/// - the previous word ends a sentence and the cue is already longer than
///   ``minSentenceCueDuration``
/// - the speaker changes
/// - adding the word would push the cue past ``maxCueChars``
/// - adding the word would push the cue past ``maxCueDuration``
///
/// A cue ends at its last word's end, or one second after that word's start
/// when the provider omitted an end.
public struct CueBuilder: Sendable {
    /// The longest a cue may run, in seconds.
    public var maxCueDuration: Double = 7
    /// The most characters a cue may carry, across both lines.
    public var maxCueChars: Int = 84
    /// The most characters one rendered line may carry.
    public var maxLineChars: Int = 42
    /// The silence between words, in seconds, that forces a new cue.
    public var gapThreshold: Double = 0.8
    /// How long a cue must run before sentence-ending punctuation splits it.
    public var minSentenceCueDuration: Double = 1.5
    /// The silence between words, in seconds, that ends a sentence even without punctuation.
    public var sentenceGapThreshold: Double = 2
    /// How many words a sentence needs before a pause alone may end it.
    public var minWordsBeforePause: Int = 3
    /// The silence, in seconds, that ends a sentence however few words it has.
    public var longPauseThreshold: Double = 10
    /// The length, in characters, past which a sentence breaks at the next comma.
    public var sentenceSoftChars: Int = 160
    /// The most characters a sentence may carry before it is cut mid-clause.
    public var maxSentenceChars: Int = 300
    /// The longest a sentence may run, in seconds, before it is cut mid-clause.
    public var maxSentenceDuration: Double = 30

    /// The duration given to a word whose end the provider omitted.
    private static let assumedWordDuration: Double = 1.0

    private static let sentenceEndings: Set<Character> = [".", "?", "!", "\u{2026}"]

    private static let clauseEndings: Set<Character> = [",", ";", ":", "\u{2014}", "\u{2013}"]

    /// Words whose full stop is an abbreviation rather than the end of a sentence.
    private static let abbreviations: Set<String> = [
        "mr.", "mrs.", "ms.", "dr.", "prof.", "st.", "jr.", "sr.", "vs.", "e.g.", "i.e.",
    ]

    /// Creates a cue builder.
    ///
    /// - Parameters:
    ///   - maxCueDuration: The longest a cue may run, in seconds.
    ///   - maxCueChars: The most characters a cue may carry.
    ///   - maxLineChars: The most characters one rendered line may carry.
    ///   - gapThreshold: The silence between words that forces a new cue.
    ///   - minSentenceCueDuration: How long a cue must run before punctuation splits it.
    ///   - sentenceGapThreshold: The silence that ends a sentence without punctuation.
    ///   - minWordsBeforePause: How many words a sentence needs before a pause may end it.
    ///   - longPauseThreshold: The silence that ends a sentence however short.
    ///   - sentenceSoftChars: The length past which a sentence breaks at a comma.
    ///   - maxSentenceChars: The most characters a sentence may carry.
    ///   - maxSentenceDuration: The longest a sentence may run, in seconds.
    public init(
        maxCueDuration: Double = 7,
        maxCueChars: Int = 84,
        maxLineChars: Int = 42,
        gapThreshold: Double = 0.8,
        minSentenceCueDuration: Double = 1.5,
        sentenceGapThreshold: Double = 2,
        minWordsBeforePause: Int = 3,
        longPauseThreshold: Double = 10,
        sentenceSoftChars: Int = 160,
        maxSentenceChars: Int = 300,
        maxSentenceDuration: Double = 30
    ) {
        self.maxCueDuration = maxCueDuration
        self.maxCueChars = maxCueChars
        self.maxLineChars = maxLineChars
        self.gapThreshold = gapThreshold
        self.minSentenceCueDuration = minSentenceCueDuration
        self.sentenceGapThreshold = sentenceGapThreshold
        self.minWordsBeforePause = minWordsBeforePause
        self.longPauseThreshold = longPauseThreshold
        self.sentenceSoftChars = sentenceSoftChars
        self.maxSentenceChars = maxSentenceChars
        self.maxSentenceDuration = maxSentenceDuration
    }

    /// A word with its start filled in, ready to be grouped into cues.
    private struct TimedWord {
        var text: String
        var start: Double
        var end: Double?
        var speaker: String?

        /// The end time to use for arithmetic, which is the start for a word with no end.
        var effectiveEnd: Double { max(end ?? start, start) }
    }

    /// Returns cues built from word timings.
    ///
    /// When there are no words, the whole transcript becomes one untimed segment
    /// so that plain text and JSON output still have something to render. That
    /// segment has no timings, which is what makes the subtitle formatters
    /// report ``CLIError/noTimingData(provider:)``.
    ///
    /// - Parameters:
    ///   - words: The provider's words, in any order.
    ///   - fallbackText: The full transcript, used when there are no words.
    ///   - duration: The audio duration, used as the untimed segment's end.
    /// - Returns: Cues in start order.
    public func segments(
        from words: [TranscriptDocument.Word],
        fallbackText: String,
        duration: Double?
    ) -> [TranscriptDocument.Segment] {
        let timed = Self.normalized(words)
        guard !timed.isEmpty else {
            let text = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return [] }
            return [TranscriptDocument.Segment(start: 0, end: duration ?? 0, text: text)]
        }

        var cues: [TranscriptDocument.Segment] = []
        var current: [TimedWord] = []

        func flush() {
            guard let cue = Self.cue(from: current) else {
                current = []
                return
            }
            cues.append(cue)
            current = []
        }

        for word in timed {
            if let previous = current.last, let first = current.first, shouldBreak(before: word, after: previous, cueStart: first.start, cueText: Self.text(of: current)) {
                flush()
            }
            current.append(word)
        }
        flush()
        return cues
    }

    /// Returns one segment per sentence, for `--cues sentences` and timestamped text.
    ///
    /// A new sentence starts when any of these holds:
    ///
    /// - the previous word ends in `.`, `?`, `!`, or `…`, unless it is a common
    ///   abbreviation such as `Mr.`
    /// - the gap to the previous word is longer than ``sentenceGapThreshold``
    ///   , the sentence already has ``minWordsBeforePause`` words, and the next
    ///   word does not start in lowercase. That catches a speaker trailing off
    ///   without punctuation, while a lone "So" or "Um", or a clause that
    ///   carries on in lowercase after the pause, stays on one line
    /// - the gap is longer than ``longPauseThreshold``, however short the sentence
    /// - the speaker changes
    /// - the sentence is past ``sentenceSoftChars`` and the previous word ends a
    ///   clause with `,`, `;`, `:`, or a dash
    /// - adding the word would push the sentence past ``maxSentenceChars`` or
    ///   ``maxSentenceDuration``
    ///
    /// The `--max-cue-*` limits do not apply, because a sentence is cut where the
    /// speaker paused rather than where a subtitle line fills up.
    ///
    /// - Parameter words: The provider's words, in any order.
    /// - Returns: Sentences in start order, empty when there are no words.
    public func sentences(from words: [TranscriptDocument.Word]) -> [TranscriptDocument.Segment] {
        var sentences: [TranscriptDocument.Segment] = []
        var current: [TimedWord] = []

        for word in Self.normalized(words) {
            if let previous = current.last, let first = current.first,
               shouldBreakSentence(
                   before: word,
                   after: previous,
                   sentenceStart: first.start,
                   sentenceText: Self.text(of: current),
                   wordCount: current.count
               ) {
                if let sentence = Self.cue(from: current) { sentences.append(sentence) }
                current = []
            }
            current.append(word)
        }
        if let sentence = Self.cue(from: current) { sentences.append(sentence) }
        return sentences
    }

    /// Returns one cue per word, for `--cues words`.
    ///
    /// Words with no end run for one second, which the subtitle formatters then
    /// clamp so that a cue never ends before it starts.
    ///
    /// - Parameter words: The provider's words, in any order.
    /// - Returns: One cue per word with text, in start order.
    public func wordCues(from words: [TranscriptDocument.Word]) -> [TranscriptDocument.Segment] {
        Self.normalized(words).compactMap { word in
            let text = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return TranscriptDocument.Segment(
                start: word.start,
                end: word.end ?? word.start + Self.assumedWordDuration,
                text: text,
                speaker: word.speaker
            )
        }
    }

    /// Wraps cue text onto at most two lines, breaking on word boundaries.
    ///
    /// When the text does not fit on two lines of ``maxLineChars``, the second
    /// line is allowed to run long rather than losing any words.
    ///
    /// - Parameter text: The cue text.
    /// - Returns: One or two lines, never empty unless the text is empty.
    public func wrapLines(_ text: String) -> [String] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }

        var first: [String] = []
        var length = 0
        var index = 0
        while index < words.count {
            let word = words[index]
            let added = first.isEmpty ? word.count : length + 1 + word.count
            if !first.isEmpty, added > maxLineChars { break }
            first.append(word)
            length = added
            index += 1
        }

        let rest = words[index...]
        guard !rest.isEmpty else { return [first.joined(separator: " ")] }
        return [first.joined(separator: " "), rest.joined(separator: " ")]
    }

    /// Returns whether `word` starts a new cue.
    private func shouldBreak(
        before word: TimedWord,
        after previous: TimedWord,
        cueStart: Double,
        cueText: String
    ) -> Bool {
        if word.start - previous.effectiveEnd > gapThreshold { return true }
        if previous.speaker != word.speaker { return true }
        if Self.endsSentence(previous.text), previous.effectiveEnd - cueStart > minSentenceCueDuration { return true }

        let trimmed = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, cueText.count + 1 + trimmed.count > maxCueChars { return true }
        if word.effectiveEnd - cueStart > maxCueDuration { return true }
        return false
    }

    /// Returns whether `word` starts a new sentence.
    private func shouldBreakSentence(
        before word: TimedWord,
        after previous: TimedWord,
        sentenceStart: Double,
        sentenceText: String,
        wordCount: Int
    ) -> Bool {
        if Self.endsSentence(previous.text), !Self.isAbbreviation(previous.text) { return true }
        let gap = word.start - previous.effectiveEnd
        if gap > longPauseThreshold { return true }
        if gap > sentenceGapThreshold, wordCount >= minWordsBeforePause, !Self.continuesSentence(word.text) {
            return true
        }
        if previous.speaker != word.speaker { return true }
        if sentenceText.count >= sentenceSoftChars, Self.endsClause(previous.text) { return true }
        if sentenceText.count + 1 + word.text.count > maxSentenceChars { return true }
        if word.effectiveEnd - sentenceStart > maxSentenceDuration { return true }
        return false
    }

    /// Fills in missing starts and puts the words in start order.
    ///
    /// A word with no start inherits the previous word's end, so providers that
    /// omit timings on filler tokens still land inside the right cue. Sorting
    /// runs afterwards and is stable, so words that share a start keep the order
    /// the provider sent them in.
    private static func normalized(_ words: [TranscriptDocument.Word]) -> [TimedWord] {
        var timed: [TimedWord] = []
        timed.reserveCapacity(words.count)
        var previousEnd: Double = 0

        for word in words {
            let text = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let start = word.start ?? previousEnd
            let entry = TimedWord(text: text, start: start, end: word.end, speaker: word.speaker)
            previousEnd = entry.effectiveEnd
            timed.append(entry)
        }

        return timed
            .enumerated()
            .sorted { left, right in
                if left.element.start == right.element.start { return left.offset < right.offset }
                return left.element.start < right.element.start
            }
            .map(\.element)
    }

    /// Returns the cue for a run of words, or `nil` when the run has no text.
    private static func cue(from words: [TimedWord]) -> TranscriptDocument.Segment? {
        guard let first = words.first, let last = words.last else { return nil }
        let text = self.text(of: words)
        guard !text.isEmpty else { return nil }
        return TranscriptDocument.Segment(
            start: first.start,
            end: last.end ?? last.start + assumedWordDuration,
            text: text,
            speaker: first.speaker
        )
    }

    /// Returns the joined text of a run of words.
    private static func text(of words: [TimedWord]) -> String {
        words.map(\.text).joined(separator: " ")
    }

    /// Returns whether a word ends a sentence.
    private static func endsSentence(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        if sentenceEndings.contains(last) { return true }
        // Allow a closing quote or bracket after the punctuation, as in `said."`
        let closers: Set<Character> = ["\"", "\u{201D}", "'", "\u{2019}", ")", "]"]
        guard closers.contains(last) else { return false }
        let withoutCloser = text.dropLast()
        guard let previous = withoutCloser.last else { return false }
        return sentenceEndings.contains(previous)
    }

    /// Returns whether a word ends a clause with a comma, semicolon, colon, or dash.
    private static func endsClause(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return clauseEndings.contains(last)
    }

    /// Returns whether a word reads as the middle of a sentence: it starts with
    /// a lowercase letter, after any opening quote or bracket.
    ///
    /// Providers that punctuate capitalise the first word of a sentence, so a
    /// lowercase word after a pause is the same sentence carrying on.
    private static func continuesSentence(_ text: String) -> Bool {
        guard let first = text.first(where: { $0.isLetter || $0.isNumber }) else { return false }
        return first.isLowercase
    }

    /// Returns whether a word is an abbreviation whose full stop ends no sentence.
    private static func isAbbreviation(_ text: String) -> Bool {
        abbreviations.contains(text.lowercased())
    }
}
