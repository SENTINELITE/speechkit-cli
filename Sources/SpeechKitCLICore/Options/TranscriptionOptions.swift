import ArgumentParser
import Foundation
import SpeechKit

/// How ElevenLabs Scribe v3 writes numbers, for `--numbers`.
public enum NumbersFormat: String, ExpressibleByArgument, CaseIterable, Sendable {
    /// Numbers are written as digits, such as `42`.
    case digits
    /// Numbers are written as words, such as `forty-two`.
    case words

    /// The matching SpeechKit value.
    public var elevenLabsFormat: ElevenLabsNumbersFormat {
        switch self {
        case .digits: return .digits
        case .words: return .words
        }
    }
}

/// How a transcript is produced.
public struct TranscriptionOptions: ParsableArguments, Sendable {
    /// Language hints. Repeat the flag for providers that accept several.
    @Option(name: [.customShort("l"), .long], help: "Language code such as en or en-US. Repeatable.")
    public var language: [String] = []

    /// The provider model identifier.
    @Option(name: [.customShort("m"), .long], help: "Provider model identifier.")
    public var model: String?

    /// A long-lived API key for this run.
    @Option(name: .long, help: "API key for this run. Overrides the environment.")
    public var apiKey: String?

    /// An endpoint override, for proxies.
    @Option(name: .long, help: "Override the provider file endpoint.")
    public var endpoint: String?

    @Option(name: .long, help: "Gemini Files API endpoint. Required with a custom Gemini --endpoint, on the same origin.")
    public var filesEndpoint: String?

    /// A request timeout, in seconds.
    @Option(name: .long, help: "Request timeout in seconds.")
    public var timeout: Double?

    /// A prompt, for providers that accept one.
    @Option(name: .long, help: "Prompt text for providers that accept one.")
    public var prompt: String?

    /// Vocabulary hints. Repeat the flag for several.
    @Option(name: .long, help: "Vocabulary hint. ElevenLabs keyterms, OpenAI keywords, Meta keywords, Gemini custom vocabulary, Apple contextual strings. Repeatable.")
    public var keyword: [String] = []

    /// Requests word-level timestamps.
    @Flag(name: .long, help: "Request word-level timestamps.")
    public var words: Bool = false

    /// Refuses to fetch an on-device model that is not cached yet.
    @Flag(name: .long, help: "Fail instead of downloading a missing on-device model.")
    public var noDownload: Bool = false

    /// Requests speaker labels.
    @Flag(name: .long, help: "Request speaker labels.")
    public var diarize: Bool = false

    /// The maximum number of speakers ElevenLabs should label.
    @Option(name: .long, help: "ElevenLabs: maximum number of speakers, 1-32. Requires --diarize.")
    public var speakers: Int?

    /// How ElevenLabs Scribe v3 writes numbers.
    @Option(name: .long, help: "ElevenLabs Scribe v3: write numbers as digits or words.")
    public var numbers: NumbersFormat?

    /// Another language expected in the audio. Repeat the flag for several.
    @Option(name: .long, help: "ElevenLabs Scribe v3: another language expected in the audio. Repeatable.")
    public var secondaryLanguage: [String] = []

    /// Requests audio event tags such as laughter.
    @Flag(name: .long, help: "ElevenLabs: tag audio events such as laughter.")
    public var tagAudioEvents: Bool = false

    /// Removes filler words and false starts.
    @Flag(name: .long, help: "ElevenLabs: remove filler words and false starts.")
    public var noVerbatim: Bool = false

    /// Creates empty transcription options.
    public init() {}
}
