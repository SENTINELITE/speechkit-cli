import ArgumentParser
import Foundation

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
    @Option(name: .long, help: "Vocabulary hint. Repeatable.")
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

    /// Creates empty transcription options.
    public init() {}
}
