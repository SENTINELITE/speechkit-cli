import Foundation

/// Renders a transcript as plain text.
///
/// With speaker labels on, the transcript is written as one paragraph per
/// speaker turn, prefixed with the speaker label and a colon.
public struct PlainTextFormatter: TranscriptFormatter {
    /// A Boolean value indicating whether speaker labels are written.
    public let includesSpeakerLabels: Bool

    /// The `txt` file extension.
    public let fileExtension = "txt"

    /// Creates a plain text formatter.
    public init(includesSpeakerLabels: Bool = false) {
        self.includesSpeakerLabels = includesSpeakerLabels
    }

    /// Renders the document as plain text.
    public func render(_ document: TranscriptDocument) throws -> String {
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
