import Foundation

/// A provider-neutral transcript.
///
/// Every runner maps its provider response into this type, and every formatter
/// renders from it. It is a stepping stone toward a `SpeechTranscriptionResult`
/// type in SpeechKit itself, so the shape is kept deliberately small.
public struct TranscriptDocument: Codable, Sendable, Equatable {
    /// A timed span of transcript text.
    public struct Segment: Codable, Sendable, Equatable {
        /// The segment start time, in seconds.
        public var start: Double
        /// The segment end time, in seconds.
        public var end: Double
        /// The segment text.
        public var text: String
        /// The speaker label, when the provider returned one.
        public var speaker: String?

        /// Creates a segment.
        public init(start: Double, end: Double, text: String, speaker: String? = nil) {
            self.start = start
            self.end = end
            self.text = text
            self.speaker = speaker
        }
    }

    /// A single word or token with optional timing.
    public struct Word: Codable, Sendable, Equatable {
        /// The word text, verbatim from the provider.
        public var text: String
        /// The word start time, in seconds, when the provider returned one.
        public var start: Double?
        /// The word end time, in seconds, when the provider returned one.
        public var end: Double?
        /// The speaker label, when the provider returned one.
        public var speaker: String?
        /// The confidence or log probability, when the provider returned one.
        public var confidence: Double?

        /// Creates a word.
        public init(
            text: String,
            start: Double? = nil,
            end: Double? = nil,
            speaker: String? = nil,
            confidence: Double? = nil
        ) {
            self.text = text
            self.start = start
            self.end = end
            self.speaker = speaker
            self.confidence = confidence
        }
    }

    /// The provider that produced the transcript.
    public var provider: String
    /// The model identifier used, when the provider reports or accepts one.
    public var model: String?
    /// The input file path.
    public var sourceFile: String
    /// The full transcript text.
    public var text: String
    /// The detected or requested language.
    public var language: String?
    /// The audio duration, in seconds, when the provider returned one.
    public var duration: Double?
    /// Timed segments, in order.
    public var segments: [Segment]
    /// Timed words, in order.
    public var words: [Word]
    /// Notes about anything the provider could not supply.
    public var warnings: [String]
    /// The provider's original response body, populated only with `--raw`.
    public var rawJSON: String?

    private enum CodingKeys: String, CodingKey {
        case provider
        case model
        case sourceFile
        case text
        case language
        case duration
        case segments
        case words
        case warnings
        case rawJSON = "raw"
    }

    /// Creates a transcript document.
    public init(
        provider: String,
        model: String? = nil,
        sourceFile: String,
        text: String,
        language: String? = nil,
        duration: Double? = nil,
        segments: [Segment] = [],
        words: [Word] = [],
        warnings: [String] = [],
        rawJSON: String? = nil
    ) {
        self.provider = provider
        self.model = model
        self.sourceFile = sourceFile
        self.text = text
        self.language = language
        self.duration = duration
        self.segments = segments
        self.words = words
        self.warnings = warnings
        self.rawJSON = rawJSON
    }

    /// A Boolean value indicating whether the document carries usable timings.
    public var hasTimings: Bool {
        segments.contains { $0.end > $0.start }
    }
}
