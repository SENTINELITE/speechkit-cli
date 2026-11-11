import Foundation
import SpeechKit

/// The ElevenLabs-only transcription flags, gathered in one value so
/// ``RunContext`` stays readable.
public struct ElevenLabsRequestOptions: Sendable, Equatable {
    /// The `--speakers` value: the maximum number of speakers, from 1 to 32.
    public var speakerCount: Int?
    /// The `--numbers` value: how Scribe v3 writes numbers.
    public var numbersFormat: ElevenLabsNumbersFormat?
    /// The `--secondary-language` values: other languages expected in the audio.
    public var secondaryLanguages: [String]
    /// Whether `--tag-audio-events` was passed.
    public var tagAudioEvents: Bool
    /// Whether `--no-verbatim` was passed.
    public var noVerbatim: Bool

    /// Creates ElevenLabs request options.
    public init(
        speakerCount: Int? = nil,
        numbersFormat: ElevenLabsNumbersFormat? = nil,
        secondaryLanguages: [String] = [],
        tagAudioEvents: Bool = false,
        noVerbatim: Bool = false
    ) {
        self.speakerCount = speakerCount
        self.numbersFormat = numbersFormat
        self.secondaryLanguages = secondaryLanguages
        self.tagAudioEvents = tagAudioEvents
        self.noVerbatim = noVerbatim
    }

    /// The first flag that was passed, as its command-line spelling.
    ///
    /// ``ProviderRegistry/makeRunner(for:context:)`` names it in the usage
    /// error when these options reach another provider.
    public var firstSetFlag: String? {
        if speakerCount != nil { return "--speakers" }
        if numbersFormat != nil { return "--numbers" }
        if !secondaryLanguages.isEmpty { return "--secondary-language" }
        if tagAudioEvents { return "--tag-audio-events" }
        if noVerbatim { return "--no-verbatim" }
        return nil
    }
}

/// Transcribes files with ElevenLabs Scribe.
public struct ElevenLabsRunner: ProviderRunner {
    /// The ElevenLabs provider.
    public static let provider: CLIProvider = .elevenlabs

    /// The models ElevenLabs accepts for file transcription.
    ///
    /// The realtime Scribe models are rejected by the upload endpoint, so they
    /// are not offered here. Scribe v1 is gone: ElevenLabs removed it on
    /// July 9, 2026.
    public static let fileModelIDs: [ElevenLabsModelID] = [.scribeV3, .scribeV2, .scribeV2Medical]

    /// How long one upload may take when `--timeout` is absent.
    static let defaultTimeout: TimeInterval = 15 * 60

    /// The token types ElevenLabs uses for whitespace between words.
    private static let spacingTypes: Set<String> = ["spacing", "space"]

    private let context: RunContext

    /// Creates an ElevenLabs runner.
    public init(context: RunContext) {
        self.context = context
    }

    /// Checks the model, the language, and the flag combinations before any
    /// upload starts.
    ///
    /// - Throws: ``CLIError`` when `--model`, `--language`, or the ElevenLabs
    ///   flags are not ones ElevenLabs accepts.
    public func validate() async throws {
        let modelID = try resolvedModelID()
        _ = try LanguageMapping.elevenLabs(context.languages)
        for code in context.elevenLabs.secondaryLanguages {
            _ = try LanguageMapping.elevenLabs([code])
        }
        if let speakers = context.elevenLabs.speakerCount {
            guard context.wantsDiarization else {
                throw CLIError.usage("--speakers requires --diarize.")
            }
            guard (1...32).contains(speakers) else {
                throw CLIError.usage("--speakers must be between 1 and 32.")
            }
        }
        if modelID != .scribeV3,
           context.elevenLabs.numbersFormat != nil || !context.elevenLabs.secondaryLanguages.isEmpty {
            throw CLIError.usage("--numbers and --secondary-language require scribe_v3.")
        }
    }

    /// Transcribes one file with ElevenLabs.
    public func transcribe(file: URL) async throws -> TranscriptDocument {
        let credential = try context.requireCredential(for: Self.provider)
        let modelID = try resolvedModelID()
        let language = try LanguageMapping.elevenLabs(context.languages)
        var warnings = RunnerSupport.droppedOptionWarnings(
            prompt: context.prompt,
            for: Self.provider
        )
        if context.languages.count > 1, let language {
            warnings.append("ElevenLabs takes one language code; only \(language) was sent.")
        }

        let options = Self.options(
            modelID: modelID,
            language: language,
            request: context.elevenLabs,
            keyterms: context.keywords,
            wantsDiarization: context.wantsDiarization,
            timeout: context.timeout
        )
        let configuration = ElevenLabsConfiguration(
            credential: credential,
            fileTranscriptionModelID: modelID,
            fileEndpoint: context.endpoint
        )
        let response = try await Self.send(file: file, configuration: configuration, options: options)
        return Self.map(
            response,
            file: file,
            modelID: modelID,
            warnings: warnings,
            cueBuilder: context.cueBuilder
        )
    }

    /// Returns the request options for a run.
    ///
    /// `--keyword` maps to ElevenLabs keyterms, and `--diarize` turns word-level
    /// speaker labels on. Scribe v3-only fields stay empty for the other
    /// models, which ``validate()`` has already refused them for.
    static func options(
        modelID: ElevenLabsModelID,
        language: String?,
        request: ElevenLabsRequestOptions,
        keyterms: [String],
        wantsDiarization: Bool,
        timeout: TimeInterval?
    ) -> ElevenLabsFileTranscriptionOptions {
        ElevenLabsFileTranscriptionOptions(
            modelID: modelID,
            language: language,
            secondaryLanguages: request.secondaryLanguages,
            numbersFormat: request.numbersFormat,
            diarize: wantsDiarization,
            speakerCount: request.speakerCount,
            keyterms: keyterms,
            tagAudioEvents: request.tagAudioEvents,
            noVerbatim: request.noVerbatim,
            timeoutInterval: timeout ?? defaultTimeout
        )
    }

    private func resolvedModelID() throws -> ElevenLabsModelID {
        try RunnerSupport.resolveModel(
            context.model,
            default: .scribeV3,
            provider: Self.provider,
            allowed: Self.fileModelIDs
        )
    }

    @MainActor
    private static func send(
        file: URL,
        configuration: ElevenLabsConfiguration,
        options: ElevenLabsFileTranscriptionOptions
    ) async throws -> ElevenLabsFileTranscriptionResponse {
        let service = SpeechService(elevenLabs: configuration)
        return try await service.transcribeElevenLabsAudioFile(file: file, options: options)
    }

    /// Maps an ElevenLabs response into a transcript document.
    ///
    /// Scribe interleaves spacing tokens with words. Those carry timings but no
    /// text worth keeping, so they are dropped before words and segments are
    /// built. Audio events and unaligned words can carry no `start` or `end`;
    /// the cue builder lands them at the previous word's end. Speaker labels
    /// keep ElevenLabs' own `speaker_0` form; formatters rename speakers `A`,
    /// `B` in order of appearance either way.
    public static func map(
        _ response: ElevenLabsFileTranscriptionResponse,
        file: URL,
        modelID: ElevenLabsModelID,
        warnings: [String] = [],
        cueBuilder: CueBuilder = CueBuilder()
    ) -> TranscriptDocument {
        var warnings = warnings

        let tokens = response.words ?? []
        let words = tokens
            .filter { !spacingTypes.contains($0.type.lowercased()) }
            .map { token in
                TranscriptDocument.Word(
                    text: token.text,
                    start: token.start,
                    end: token.end,
                    speaker: token.speakerID,
                    confidence: token.logprob
                )
            }
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }

        let duration = response.audioDurationSeconds ?? tokens.compactMap(\.end).max()
        let segments = cueBuilder.segments(
            from: words,
            fallbackText: response.text,
            duration: duration
        )
        if words.isEmpty {
            warnings.append("ElevenLabs returned no word timings; the transcript is one untimed segment.")
        }

        return TranscriptDocument(
            provider: CLIProvider.elevenlabs.rawValue,
            model: modelID.rawValue,
            sourceFile: file.path,
            text: response.text,
            language: response.languageCode,
            duration: duration,
            segments: segments,
            words: words,
            warnings: warnings
        )
    }
}
