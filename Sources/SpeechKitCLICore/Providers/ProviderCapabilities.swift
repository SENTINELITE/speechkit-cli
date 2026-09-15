import Foundation

/// How a provider expects `--language` values.
public enum LanguageStyle: String, Sendable, Equatable {
    /// The provider takes no language input.
    case none
    /// Two-letter ISO 639-1 codes.
    case iso639
    /// BCP-47 language tags.
    case bcp47
    /// A fixed provider enumeration of codes.
    case providerEnum
    /// Language names rather than codes.
    case languageName
    /// A `Locale` identifier.
    case locale
}

/// What one provider can do.
public struct ProviderCapabilities: Sendable, Equatable {
    /// Whether the provider returns word-level timestamps.
    public let supportsWordTimestamps: Bool
    /// Whether the provider returns timed segments.
    public let supportsSegments: Bool
    /// Whether the provider labels speakers.
    public let supportsDiarization: Bool
    /// How the provider expects language values.
    public let languageStyle: LanguageStyle
    /// The upload size limit, in bytes, when the provider has one.
    public let maxFileBytes: Int64?
    /// Whether the provider needs macOS 26 or later.
    public let requiresMacOS26: Bool

    /// Creates a capability record.
    public init(
        supportsWordTimestamps: Bool,
        supportsSegments: Bool,
        supportsDiarization: Bool,
        languageStyle: LanguageStyle,
        maxFileBytes: Int64?,
        requiresMacOS26: Bool = false
    ) {
        self.supportsWordTimestamps = supportsWordTimestamps
        self.supportsSegments = supportsSegments
        self.supportsDiarization = supportsDiarization
        self.languageStyle = languageStyle
        self.maxFileBytes = maxFileBytes
        self.requiresMacOS26 = requiresMacOS26
    }

    /// Returns the capabilities of a provider.
    ///
    /// The byte limits mirror the private limits in SpeechKit's upload clients.
    public static func capabilities(for provider: CLIProvider) -> ProviderCapabilities {
        switch provider {
        case .elevenlabs:
            return ProviderCapabilities(
                supportsWordTimestamps: true,
                supportsSegments: true,
                supportsDiarization: false,
                languageStyle: .none,
                maxFileBytes: 3 * 1024 * 1024 * 1024
            )
        case .aqua:
            return ProviderCapabilities(
                supportsWordTimestamps: false,
                supportsSegments: false,
                supportsDiarization: false,
                languageStyle: .providerEnum,
                maxFileBytes: 25 * 1024 * 1024
            )
        case .cohere:
            return ProviderCapabilities(
                supportsWordTimestamps: false,
                supportsSegments: false,
                supportsDiarization: false,
                languageStyle: .providerEnum,
                maxFileBytes: 25 * 1024 * 1024
            )
        case .grok:
            return ProviderCapabilities(
                supportsWordTimestamps: true,
                supportsSegments: true,
                supportsDiarization: true,
                languageStyle: .providerEnum,
                maxFileBytes: 500 * 1024 * 1024
            )
        case .openai:
            return ProviderCapabilities(
                supportsWordTimestamps: true,
                supportsSegments: true,
                supportsDiarization: true,
                languageStyle: .iso639,
                maxFileBytes: 25 * 1024 * 1024
            )
        case .meta:
            return ProviderCapabilities(
                supportsWordTimestamps: false,
                supportsSegments: true,
                supportsDiarization: true,
                languageStyle: .languageName,
                maxFileBytes: 32 * 1024 * 1024
            )
        case .gemini:
            return ProviderCapabilities(
                supportsWordTimestamps: true,
                supportsSegments: true,
                supportsDiarization: true,
                languageStyle: .bcp47,
                maxFileBytes: 100 * 1024 * 1024
            )
        case .apple:
            return ProviderCapabilities(
                supportsWordTimestamps: true,
                supportsSegments: true,
                supportsDiarization: false,
                languageStyle: .locale,
                maxFileBytes: nil,
                requiresMacOS26: true
            )
        }
    }
}
