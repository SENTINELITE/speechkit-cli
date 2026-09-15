import Foundation
import SpeechKit

/// Everything a runner needs to transcribe one file.
public struct RunContext: Sendable {
    /// The resolved credential, or `nil` for providers that need none.
    public var credential: SpeechCredential?
    /// The model identifier requested with `--model`.
    public var model: String?
    /// The language codes requested with `--language`.
    public var languages: [String]
    /// An endpoint override for proxies.
    public var endpoint: URL?
    /// A request timeout override, in seconds.
    public var timeout: TimeInterval?
    /// A prompt for providers that accept one.
    public var prompt: String?
    /// Vocabulary hints.
    public var keywords: [String]
    /// Whether word-level timestamps were requested.
    public var wantsWords: Bool
    /// Whether speaker labels were requested.
    public var wantsDiarization: Bool
    /// Whether the provider's raw response should be kept.
    public var includeRaw: Bool
    /// The longest subtitle cue, in seconds.
    public var maxCueDuration: Double
    /// The longest subtitle cue, in characters.
    public var maxCueChars: Int
    /// Whether subtitle cues come from segments or from single words.
    public var cueMode: CueMode

    /// Creates a run context.
    public init(
        credential: SpeechCredential? = nil,
        model: String? = nil,
        languages: [String] = [],
        endpoint: URL? = nil,
        timeout: TimeInterval? = nil,
        prompt: String? = nil,
        keywords: [String] = [],
        wantsWords: Bool = false,
        wantsDiarization: Bool = false,
        includeRaw: Bool = false,
        maxCueDuration: Double = 7,
        maxCueChars: Int = 84,
        cueMode: CueMode = .segments
    ) {
        self.credential = credential
        self.model = model
        self.languages = languages
        self.endpoint = endpoint
        self.timeout = timeout
        self.prompt = prompt
        self.keywords = keywords
        self.wantsWords = wantsWords
        self.wantsDiarization = wantsDiarization
        self.includeRaw = includeRaw
        self.maxCueDuration = maxCueDuration
        self.maxCueChars = maxCueChars
        self.cueMode = cueMode
    }

    /// A cue builder carrying the limits from the command line.
    public var cueBuilder: CueBuilder {
        CueBuilder(maxCueDuration: maxCueDuration, maxCueChars: maxCueChars)
    }

    /// Returns the credential, or throws when the provider requires one.
    ///
    /// - Throws: ``CLIError/missingCredential(_:)`` when no credential was resolved.
    public func requireCredential(for provider: CLIProvider) throws -> SpeechCredential {
        guard let credential else {
            throw CLIError.missingCredential(provider)
        }
        return credential
    }
}

/// Transcribes files with one provider and maps the response into a ``TranscriptDocument``.
public protocol ProviderRunner: Sendable {
    /// The provider this runner serves.
    static var provider: CLIProvider { get }

    /// Creates a runner for one command invocation.
    init(context: RunContext)

    /// Transcribes one audio file.
    ///
    /// - Throws: ``CLIError`` for configuration problems, or a `SpeechError` from the provider.
    func transcribe(file: URL) async throws -> TranscriptDocument
}

extension ProviderRunner {
    /// The note added when `--raw` is passed but the provider response body is not reachable.
    static var rawUnavailableWarning: String {
        "--raw is not available for \(Self.provider.rawValue) yet; SpeechKit returns decoded values only."
    }
}
