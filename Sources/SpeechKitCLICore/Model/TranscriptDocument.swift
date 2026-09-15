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

    /// What a provider reported about the cost of producing the transcript.
    ///
    /// Every field is optional because no provider reports all of them, and the
    /// whole value is optional on the document so a transcript from a provider
    /// that reports nothing encodes exactly the JSON it always did.
    public struct Metrics: Codable, Sendable, Equatable {
        /// The compute time the provider spent, in seconds, when it reports one.
        ///
        /// This is the provider's own number, not the wall time of the call, so
        /// it excludes upload and queueing. VOZ reports it; the cloud providers
        /// do not.
        public var processingSeconds: Double?
        /// The billable audio seconds the provider counted.
        public var billedSeconds: Double?
        /// The input tokens the provider counted.
        public var inputTokens: Int?
        /// The output tokens the provider counted.
        public var outputTokens: Int?
        /// The total tokens the provider counted.
        public var totalTokens: Int?

        /// Creates a metrics record.
        public init(
            processingSeconds: Double? = nil,
            billedSeconds: Double? = nil,
            inputTokens: Int? = nil,
            outputTokens: Int? = nil,
            totalTokens: Int? = nil
        ) {
            self.processingSeconds = processingSeconds
            self.billedSeconds = billedSeconds
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
            self.totalTokens = totalTokens
        }

        /// A Boolean value indicating whether the provider reported nothing at all.
        ///
        /// Runners use this to leave ``TranscriptDocument/metrics`` `nil` rather
        /// than attach a record of five `null`s.
        public var isEmpty: Bool {
            processingSeconds == nil
                && billedSeconds == nil
                && inputTokens == nil
                && outputTokens == nil
                && totalTokens == nil
        }

        /// Returns the record, or `nil` when the provider reported nothing.
        public var nonEmpty: Metrics? {
            isEmpty ? nil : self
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
    /// What the provider reported about time, billing, and tokens.
    ///
    /// This is `nil` for providers that report none of it, and a `nil` property
    /// is omitted from the encoded JSON, so adding it changed no existing
    /// output.
    public var metrics: Metrics?

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
        metrics: Metrics? = nil
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
        self.metrics = metrics
    }

    /// A Boolean value indicating whether the document carries usable timings.
    public var hasTimings: Bool {
        segments.contains { $0.end > $0.start }
    }
}
