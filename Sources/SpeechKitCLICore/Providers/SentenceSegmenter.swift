import Foundation

/// Builds segments from word timings using the default cue rules.
///
/// Runners that have words but no provider segments call this. It is a thin
/// front for ``CueBuilder`` with the default limits, kept because every runner
/// already calls it and the limits only differ when the command line overrides
/// them, in which case runners use ``RunContext/cueBuilder`` directly.
public enum SentenceSegmenter {
    /// Returns segments built from words, or one untimed segment when there are none.
    ///
    /// - Parameters:
    ///   - words: The provider's words, in any order.
    ///   - fallbackText: The full transcript, used when there are no words.
    ///   - duration: The audio duration, used as the untimed segment's end.
    public static func segments(
        from words: [TranscriptDocument.Word],
        fallbackText: String,
        duration: Double?
    ) -> [TranscriptDocument.Segment] {
        CueBuilder().segments(from: words, fallbackText: fallbackText, duration: duration)
    }
}
