import Foundation

/// Renders a transcript as plain text.
///
/// With timestamps on and timings available, the transcript is written one
/// sentence per line, each prefixed with its start time:
///
/// ```
/// 6:40.5  That night he was more tired than he ever had been.
/// 6:45.8  He ate an early supper.
/// ```
///
/// A silence longer than ``paragraphGap`` between two sentences leaves a blank
/// line, so a recording with long pauses reads in sections. Sentences come
/// from the word timings when the provider returned any, and from the
/// segments otherwise. A transcript with no timings at all falls back
/// to prose. With speaker labels on, each line carries its label after the
/// time; without timestamps, the transcript is one paragraph per speaker turn.
public struct PlainTextFormatter: TranscriptFormatter {
    /// A Boolean value indicating whether speaker labels are written.
    public let includesSpeakerLabels: Bool
    /// A Boolean value indicating whether lines are timestamped.
    public let includesTimestamps: Bool
    /// The builder that groups words into sentences.
    public let cueBuilder: CueBuilder
    /// The silence, in seconds, between two sentences that starts a new paragraph.
    public let paragraphGap: Double

    /// The `txt` file extension.
    public let fileExtension = "txt"

    /// Creates a plain text formatter.
    ///
    /// - Parameters:
    ///   - includesSpeakerLabels: Whether speaker labels are written.
    ///   - includesTimestamps: Whether to write one timestamped sentence per line.
    ///   - cueBuilder: The builder that groups words into sentences.
    ///   - paragraphGap: The silence between sentences that starts a new paragraph.
    public init(
        includesSpeakerLabels: Bool = false,
        includesTimestamps: Bool = false,
        cueBuilder: CueBuilder = CueBuilder(),
        paragraphGap: Double = 10
    ) {
        self.includesSpeakerLabels = includesSpeakerLabels
        self.includesTimestamps = includesTimestamps
        self.cueBuilder = cueBuilder
        self.paragraphGap = paragraphGap
    }

    /// Renders the document as plain text.
    public func render(_ document: TranscriptDocument) throws -> String {
        if includesTimestamps, let lines = timestampedLines(document) {
            return lines.joined(separator: "\n") + "\n"
        }

        guard includesSpeakerLabels else {
            return document.text + "\n"
        }

        let turns = SpeakerLabels.turns(in: document.segments)
        guard !turns.isEmpty else {
            return document.text + "\n"
        }

        let paragraphs = turns.map { "\($0.label): \($0.text)" }
        return paragraphs.joined(separator: "\n\n") + "\n"
    }

    /// Returns one line per sentence, or `nil` when the document has no timings.
    ///
    /// Times are padded to the widest one, so the text lines up in a column.
    private func timestampedLines(_ document: TranscriptDocument) -> [String]? {
        let sentences: [TranscriptDocument.Segment]
        if document.words.contains(where: { $0.start != nil }) {
            sentences = cueBuilder.sentences(from: document.words)
        } else if document.hasTimings {
            sentences = document.segments
        } else {
            return nil
        }
        guard !sentences.isEmpty else { return nil }

        let labels = includesSpeakerLabels
            ? SpeakerLabels.labels(in: sentences)
            : Array(repeating: nil, count: sentences.count)
        let times = sentences.map { TimecodeFormatter.clock($0.start) }
        let width = times.map(\.count).max() ?? 0

        var lines: [String] = []
        var previousEnd: Double?
        for (sentence, (time, label)) in zip(sentences, zip(times, labels)) {
            if let previousEnd, sentence.start - previousEnd > paragraphGap {
                lines.append("")
            }
            previousEnd = sentence.end
            let padded = String(repeating: " ", count: width - time.count) + time
            let text = sentence.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = label.map { "\($0): " } ?? ""
            lines.append("\(padded)  \(prefix)\(text)")
        }
        return lines
    }
}

/// Groups segments into speaker turns and names the speakers `A`, `B`, `C`, and so on.
public enum SpeakerLabels {
    /// One run of consecutive segments spoken by the same speaker.
    public struct Turn: Sendable, Equatable {
        /// The display label, such as `A`.
        public let label: String
        /// The joined, whitespace-normalized text of the run.
        public let text: String
    }

    /// Returns the speaker turns in a list of segments.
    public static func turns(in segments: [TranscriptDocument.Segment]) -> [Turn] {
        var assigned: [String: String] = [:]
        var nextIndex = 0
        var turns: [Turn] = []
        var currentKey: String?
        var currentText: [String] = []

        func flush() {
            guard let key = currentKey, !currentText.isEmpty else { return }
            turns.append(Turn(label: assigned[key] ?? key, text: currentText.joined(separator: " ")))
            currentText = []
        }

        for segment in segments {
            let key = segment.speaker ?? "?"
            if assigned[key] == nil {
                assigned[key] = label(at: nextIndex)
                nextIndex += 1
            }
            if key != currentKey {
                flush()
                currentKey = key
            }
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { currentText.append(text) }
        }
        flush()
        return turns
    }

    /// Returns the display label for each segment, or `nil` where a segment has
    /// no speaker and none of the segments do.
    ///
    /// Labels are assigned in order of first appearance, so the first speaker
    /// heard is `A`. Segments with no speaker in an otherwise labelled
    /// transcript share one label, because the provider gave nothing to tell
    /// them apart.
    public static func labels(in segments: [TranscriptDocument.Segment]) -> [String?] {
        guard segments.contains(where: { $0.speaker != nil }) else {
            return Array(repeating: nil, count: segments.count)
        }
        var assigned: [String: String] = [:]
        var nextIndex = 0
        return segments.map { segment in
            let key = segment.speaker ?? "?"
            if let existing = assigned[key] { return existing }
            let label = self.label(at: nextIndex)
            assigned[key] = label
            nextIndex += 1
            return label
        }
    }

    /// Returns the label for a zero-based speaker index: `A`, `B`, ... `Z`, `AA`.
    public static func label(at index: Int) -> String {
        var remaining = index
        var label = ""
        repeat {
            let scalarValue = UnicodeScalar(UInt8(65 + (remaining % 26)))
            label = String(Character(scalarValue)) + label
            remaining = remaining / 26 - 1
        } while remaining >= 0
        return label
    }
}
