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
    public var filesEndpoint: URL?
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
    /// The longest subtitle cue, in seconds.
    public var maxCueDuration: Double
    /// The longest subtitle cue, in characters.
    public var maxCueChars: Int
    /// Whether subtitle cues come from segments or from single words.
    public var cueMode: CueMode
    /// Whether a provider may fetch an on-device model it does not have yet.
    ///
    /// `--no-download` sets this to `false` so a script never triggers a
    /// surprise several-hundred-megabyte download.
    public var allowsModelDownload: Bool
    /// The console model preparation reports progress on.
    public var console: Console

    /// Creates a run context.
    public init(
        credential: SpeechCredential? = nil,
        model: String? = nil,
        languages: [String] = [],
        endpoint: URL? = nil,
        filesEndpoint: URL? = nil,
        timeout: TimeInterval? = nil,
        prompt: String? = nil,
        keywords: [String] = [],
        wantsWords: Bool = false,
        wantsDiarization: Bool = false,
        maxCueDuration: Double = 7,
        maxCueChars: Int = 84,
        cueMode: CueMode = .segments,
        allowsModelDownload: Bool = true,
        console: Console = Console()
    ) {
        self.credential = credential
        self.model = model
        self.languages = languages
        self.endpoint = endpoint
        self.filesEndpoint = filesEndpoint
        self.timeout = timeout
        self.prompt = prompt
        self.keywords = keywords
        self.wantsWords = wantsWords
        self.wantsDiarization = wantsDiarization
        self.maxCueDuration = maxCueDuration
        self.maxCueChars = maxCueChars
        self.cueMode = cueMode
        self.allowsModelDownload = allowsModelDownload
        self.console = console
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

    /// Checks the run context against what the provider accepts.
    ///
    /// ``ProviderRegistry/makeRunner(for:context:)`` calls this for every
    /// provider before any file is read, so a bad `--model`, `--language`, or
    /// flag combination exits with code 1 rather than failing per file.
    ///
    /// The method is asynchronous because Apple's list of supported locales is,
    /// and every other runner ignores that.
    ///
    /// - Throws: ``CLIError`` when the request does not match the provider.
    func validate() async throws

    /// Transcribes one audio file.
    ///
    /// - Throws: ``CLIError`` for configuration problems, or a `SpeechError` from the provider.
    func transcribe(file: URL) async throws -> TranscriptDocument

    /// Releases anything the run held after the last file finishes.
    ///
    /// Only the on-device runners implement this. VOZ keeps a multi-hundred
    /// megabyte Core ML model resident for the whole batch, and the process
    /// exits faster once it is dropped.
    func finish() async
}

extension ProviderRunner {
    /// Accepts any run context, for providers with nothing to check up front.
    public func validate() async throws {}

    /// Does nothing, for providers that hold no resources between files.
    public func finish() async {}
}
