import Foundation

/// Builds placeholder segments from word timings.
///
/// Phase 2 replaces this with `CueBuilder`, which applies gap, speaker, and cue
/// length rules. Until then, word-only providers get one segment per sentence.
public enum SentenceSegmenter {
    private static let sentenceEndings: Set<Character> = [".", "?", "!", "\u{2026}"]

    /// Returns segments built from words, or one untimed segment when there are none.
    public static func segments(
        from words: [TranscriptDocument.Word],
        fallbackText: String,
        duration: Double?
    ) -> [TranscriptDocument.Segment] {
        guard !words.isEmpty else {
            let text = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return [] }
            return [TranscriptDocument.Segment(start: 0, end: duration ?? 0, text: text)]
        }

        var segments: [TranscriptDocument.Segment] = []
        var current: [TranscriptDocument.Word] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let text = current
                .map { $0.text.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !text.isEmpty else {
                current = []
                return
            }
            segments.append(
                TranscriptDocument.Segment(
                    start: first.start ?? 0,
                    end: last.end ?? last.start ?? first.start ?? 0,
                    text: text,
                    speaker: first.speaker
                )
            )
            current = []
        }

        for word in words {
            if let speaker = current.first?.speaker, speaker != word.speaker {
                flush()
            } else if current.first != nil, current.first?.speaker == nil, word.speaker != nil {
                flush()
            }
            current.append(word)
            if let last = word.text.trimmingCharacters(in: .whitespaces).last, sentenceEndings.contains(last) {
                flush()
            }
        }
        flush()
        return segments
    }
}
