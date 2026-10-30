import Foundation
import SpeechKit

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
    /// The model identifier used for file transcription when `--model` is absent.
    ///
    /// This is `nil` for providers with no model identifier at all, which today
    /// means Apple's on-device transcriber.
    public let defaultFileModel: String?
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
    /// The lowercased file extensions the provider accepts, when it checks them.
    ///
    /// This is `nil` when SpeechKit's client for the provider performs no
    /// extension check, not when the provider accepts everything.
    public let acceptedExtensions: [String]?
    /// Whether the provider needs macOS 26 or later.
    public let requiresMacOS26: Bool

    /// Creates a capability record.
    public init(
        defaultFileModel: String?,
        supportsWordTimestamps: Bool,
        supportsSegments: Bool,
        supportsDiarization: Bool,
        languageStyle: LanguageStyle,
        maxFileBytes: Int64?,
        acceptedExtensions: [String]? = nil,
        requiresMacOS26: Bool = false
    ) {
        self.defaultFileModel = defaultFileModel
        self.supportsWordTimestamps = supportsWordTimestamps
        self.supportsSegments = supportsSegments
        self.supportsDiarization = supportsDiarization
        self.languageStyle = languageStyle
        self.maxFileBytes = maxFileBytes
        self.acceptedExtensions = acceptedExtensions
        self.requiresMacOS26 = requiresMacOS26
    }

    /// Returns the capabilities of a provider.
    ///
    /// The byte limits and extension lists mirror the private values in
    /// SpeechKit's upload clients, so a file is rejected here rather than after
    /// an upload starts.
    public static func capabilities(for provider: CLIProvider) -> ProviderCapabilities {
        switch provider {
        case .elevenlabs:
            // ElevenLabs checks size and duration but not the extension.
            return ProviderCapabilities(
                defaultFileModel: ElevenLabsModelID.scribeV2.rawValue,
                supportsWordTimestamps: true,
                supportsSegments: true,
                supportsDiarization: false,
                languageStyle: .none,
                maxFileBytes: 3 * 1024 * 1024 * 1024,
                acceptedExtensions: nil
            )
        case .aqua:
            return ProviderCapabilities(
                defaultFileModel: AquaModelID.avalonV15.rawValue,
                supportsWordTimestamps: false,
                supportsSegments: false,
                supportsDiarization: false,
                languageStyle: .providerEnum,
                maxFileBytes: 25 * 1024 * 1024,
                acceptedExtensions: ["flac", "m4a", "mp3", "mp4", "mpeg", "mpga", "ogg", "wav", "webm"]
            )
        case .cohere:
            return ProviderCapabilities(
                defaultFileModel: CohereModelID.transcribe032026.rawValue,
                supportsWordTimestamps: false,
                supportsSegments: false,
                supportsDiarization: false,
                languageStyle: .providerEnum,
                maxFileBytes: 25 * 1024 * 1024,
                acceptedExtensions: ["flac", "mp3", "mpeg", "mpga", "ogg", "wav"]
            )
        case .grok:
            return ProviderCapabilities(
                defaultFileModel: GrokModelID.stt.rawValue,
                supportsWordTimestamps: true,
                supportsSegments: true,
                supportsDiarization: true,
                languageStyle: .providerEnum,
                maxFileBytes: 500 * 1024 * 1024,
                acceptedExtensions: ["aac", "flac", "m4a", "mkv", "mp3", "mp4", "ogg", "opus", "wav"]
            )
        case .openai:
            return ProviderCapabilities(
                defaultFileModel: OpenAIFileTranscriptionModelID.gptTranscribe.rawValue,
                supportsWordTimestamps: true,
                supportsSegments: true,
                supportsDiarization: true,
                languageStyle: .iso639,
                maxFileBytes: 25 * 1024 * 1024,
                acceptedExtensions: ["m4a", "mp3", "mp4", "mpeg", "mpga", "wav", "webm"]
            )
        case .meta:
            // Meta uploads use the WAV encoding, which is the only container its
            // client accepts for prerecorded audio.
            return ProviderCapabilities(
                defaultFileModel: MetaModelID.museVoiceTranscribe1.rawValue,
                supportsWordTimestamps: false,
                supportsSegments: true,
                supportsDiarization: true,
                languageStyle: .languageName,
                maxFileBytes: 32 * 1024 * 1024,
                acceptedExtensions: ["wav"]
            )
        case .gemini:
            // Gemini caps inline requests at 100 MB but sends anything larger
            // through the Files API, so there is no single upload byte limit.
            // Its client limits duration instead: one hour per file.
            return ProviderCapabilities(
                defaultFileModel: GeminiFileTranscriptionModelID.transcribe35.rawValue,
                supportsWordTimestamps: true,
                supportsSegments: true,
                supportsDiarization: true,
                languageStyle: .bcp47,
                maxFileBytes: nil,
                acceptedExtensions: [
                    "aac", "aif", "aiff", "flac", "m4a", "mp3", "mpeg", "mpga", "ogg", "opus", "wav", "webm"
                ]
            )
        case .fishAudio:
            // SpeechKit's Fish Audio client rejects only AIFF and CAF and caps
            // duration at 60 minutes. It keeps no allow-list, so this one is
            // Fish Audio's documented formats, which also turns AIFF and CAF
            // away before upload. Fish limits upload size with a 413 but does
            // not publish the number.
            return ProviderCapabilities(
                defaultFileModel: FishAudioFileTranscriptionModelID.transcribe1Pro.rawValue,
                supportsWordTimestamps: true,
                supportsSegments: true,
                supportsDiarization: true,
                languageStyle: .iso639,
                maxFileBytes: nil,
                acceptedExtensions: [
                    "aac", "flac", "m4a", "mkv", "mov", "mp3", "mp4", "oga", "ogg", "opus", "wav", "webm"
                ]
            )
        case .apple:
            return ProviderCapabilities(
                defaultFileModel: nil,
                supportsWordTimestamps: true,
                supportsSegments: true,
                supportsDiarization: false,
                languageStyle: .locale,
                maxFileBytes: nil,
                acceptedExtensions: nil,
                requiresMacOS26: true
            )
        case .voz:
            // VOZ runs a Core ML model from disk, so there is no upload limit,
            // and `AVAudioFile` decodes whatever the system can open rather
            // than a fixed extension list.
            return ProviderCapabilities(
                defaultFileModel: VozModelSession.modelVersion,
                supportsWordTimestamps: true,
                supportsSegments: true,
                supportsDiarization: false,
                languageStyle: .none,
                maxFileBytes: nil,
                acceptedExtensions: nil
            )
        }
    }
}
