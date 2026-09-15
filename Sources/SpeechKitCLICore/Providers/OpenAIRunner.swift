import Foundation
import SpeechKit

/// Transcribes files with OpenAI.
public struct OpenAIRunner: ProviderRunner {
    /// The OpenAI provider.
    public static let provider: CLIProvider = .openai

    /// The model that returns speaker-labelled segments.
    ///
    /// SpeechKit deprecates this case because OpenAI shuts the model down on
    /// February 26, 2027, but it is still the only file model that diarizes, so
    /// it is looked up by raw value to keep the build free of the warning. The
    /// fallback never runs; the raw value is a case of the enum.
    public static let diarizeModelID = OpenAIFileTranscriptionModelID(rawValue: "gpt-4o-transcribe-diarize") ?? .gptTranscribe

    /// The model that returns word timestamps.
    ///
    /// Deprecated in SpeechKit for the same shutdown date, and still the only
    /// file model that accepts timestamp granularities.
    public static let wordsModelID = OpenAIFileTranscriptionModelID(rawValue: "whisper-1") ?? .gptTranscribe

    /// The note added when the CLI picks one of the models OpenAI is retiring.
    static func shutdownWarning(for modelID: OpenAIFileTranscriptionModelID) -> String {
        "OpenAI shuts down \(modelID.rawValue) on February 26, 2027. Until a current model returns the same data, this run uses it."
    }

    /// What one run sends to OpenAI, after the model and the flags are reconciled.
    ///
    /// SpeechKit rejects several combinations outright, so they are settled here
    /// rather than after an upload: word timestamps need `whisper-1`, speaker
    /// labels need `gpt-4o-transcribe-diarize`, and the diarizing model takes
    /// neither a prompt nor timestamp granularities.
    public struct ResolvedOptions: Sendable, Equatable {
        /// The model the run uses.
        public var modelID: OpenAIFileTranscriptionModelID
        /// The granularities the request asks for.
        public var timestampGranularities: [OpenAITimestampGranularity]
        /// The prompt, or `nil` when the model takes none.
        public var prompt: String?
        /// Whether the request carries a diarization chunking strategy.
        public var diarizes: Bool
        /// Notes about anything the flags asked for that the model cannot do.
        public var warnings: [String]

        /// The chunking strategy the configuration and options carry.
        public var diarizationChunkingStrategy: OpenAIDiarizationChunkingStrategy? {
            diarizes ? .auto : nil
        }
    }

    private let context: RunContext

    /// Creates an OpenAI runner.
    public init(context: RunContext) {
        self.context = context
    }

    /// Checks the model against the requested flags before any upload starts.
    public func validate() async throws {
        _ = try Self.resolveOptions(
            model: context.model,
            wantsWords: context.wantsWords,
            wantsDiarization: context.wantsDiarization,
            prompt: context.prompt
        )
    }

    /// Transcribes one file with OpenAI.
    public func transcribe(file: URL) async throws -> TranscriptDocument {
        let credential = try context.requireCredential(for: Self.provider)
        let resolved = try Self.resolveOptions(
            model: context.model,
            wantsWords: context.wantsWords,
            wantsDiarization: context.wantsDiarization,
            prompt: context.prompt
        )
        let languages = LanguageMapping.openAI(context.languages)
        let configuration = OpenAIConfiguration(
            credential: credential,
            fileTranscriptionModelID: resolved.modelID,
            language: languages.language,
            languages: languages.languages,
            prompt: resolved.prompt,
            keywords: context.keywords,
            diarizationChunkingStrategy: resolved.diarizationChunkingStrategy,
            timeoutInterval: context.timeout ?? 10 * 60,
            fileEndpoint: context.endpoint
        )
        let options = OpenAIFileTranscriptionOptions(
            modelID: resolved.modelID,
            language: languages.language,
            languages: languages.languages,
            prompt: resolved.prompt,
            keywords: context.keywords,
            timestampGranularities: resolved.timestampGranularities,
            diarizationChunkingStrategy: resolved.diarizationChunkingStrategy,
            timeoutInterval: context.timeout ?? 10 * 60
        )
        let response = try await Self.send(file: file, configuration: configuration, options: options)
        return Self.map(
            response,
            file: file,
            modelID: resolved.modelID,
            warnings: resolved.warnings,
            cueBuilder: context.cueBuilder
        )
    }

    /// Reconciles `--model` with `--words`, `--diarize`, and `--prompt`.
    ///
    /// With no `--model`, the flags pick the model: `--diarize` selects
    /// `gpt-4o-transcribe-diarize` and word timings select `whisper-1`, which is
    /// the only model OpenAI returns them from. With an explicit `--model`, a
    /// combination the model cannot serve is a usage error before the upload
    /// rather than a rejection after it.
    ///
    /// - Throws: ``CLIError/usage(_:)`` for a model that cannot serve the flags,
    ///   or ``CLIError/invalidModel(provider:model:valid:)`` for an unknown model.
    public static func resolveOptions(
        model: String?,
        wantsWords: Bool,
        wantsDiarization: Bool,
        prompt: String?
    ) throws -> ResolvedOptions {
        if wantsWords, wantsDiarization, model == nil {
            throw CLIError.usage(
                "openai returns word timestamps from whisper-1 and speaker labels from \(diarizeModelID.rawValue), so --words and --diarize cannot be combined. Run the file twice, or drop one flag."
            )
        }

        let defaultModel: OpenAIFileTranscriptionModelID
        if wantsDiarization {
            defaultModel = diarizeModelID
        } else if wantsWords {
            defaultModel = wordsModelID
        } else {
            defaultModel = .gptTranscribe
        }
        let modelID = try RunnerSupport.resolveModel(model, default: defaultModel, provider: .openai)

        var warnings: [String] = []
        if modelID == diarizeModelID || modelID == wordsModelID {
            warnings.append(shutdownWarning(for: modelID))
        }
        if modelID == diarizeModelID {
            // The diarizing model takes neither a prompt nor granularities, and
            // SpeechKit refuses the request outright when either is present.
            var prompt = prompt
            if prompt != nil {
                prompt = nil
                warnings.append("OpenAI's \(diarizeModelID.rawValue) takes no prompt; --prompt was dropped.")
            }
            if wantsWords {
                warnings.append("OpenAI's \(diarizeModelID.rawValue) returns segments rather than words; --words produced no word timings.")
            }
            return ResolvedOptions(
                modelID: modelID,
                timestampGranularities: [],
                prompt: prompt,
                diarizes: true,
                warnings: warnings
            )
        }

        if wantsDiarization {
            throw CLIError.usage(
                "openai returns speaker labels from \(diarizeModelID.rawValue) only, so --diarize cannot be combined with --model \(modelID.rawValue)."
            )
        }
        if wantsWords, modelID != wordsModelID {
            throw CLIError.usage(
                "openai returns word timestamps from whisper-1 only, so --words and subtitle formats cannot be combined with --model \(modelID.rawValue). Pass --model whisper-1."
            )
        }

        return ResolvedOptions(
            modelID: modelID,
            timestampGranularities: wantsWords ? [.word, .segment] : [],
            prompt: prompt,
            diarizes: false,
            warnings: warnings
        )
    }

    @MainActor
    private static func send(
        file: URL,
        configuration: OpenAIConfiguration,
        options: OpenAIFileTranscriptionOptions
    ) async throws -> OpenAIFileTranscriptionResponse {
        let service = SpeechService(openAI: configuration)
        return try await service.transcribeOpenAIAudioFile(file: file, options: options)
    }

    /// Maps an OpenAI response into a transcript document.
    public static func map(
        _ response: OpenAIFileTranscriptionResponse,
        file: URL,
        modelID: OpenAIFileTranscriptionModelID,
        warnings: [String] = [],
        cueBuilder: CueBuilder = CueBuilder()
    ) -> TranscriptDocument {
        var warnings = warnings

        let words = (response.words ?? []).map { word in
            TranscriptDocument.Word(text: word.word, start: word.start, end: word.end)
        }

        var segments: [TranscriptDocument.Segment] = []
        if let diarized = response.diarizedSegments, !diarized.isEmpty {
            segments = RunnerSupport.orderedSegments(
                diarized.map { segment in
                    TranscriptDocument.Segment(
                        start: segment.start ?? 0,
                        end: segment.end ?? segment.start ?? 0,
                        text: normalized(segment.text),
                        speaker: segment.speaker
                    )
                }
            )
        } else if let plain = response.segments, !plain.isEmpty {
            segments = RunnerSupport.orderedSegments(
                plain.map { segment in
                    TranscriptDocument.Segment(
                        start: segment.start ?? 0,
                        end: segment.end ?? segment.start ?? 0,
                        text: normalized(segment.text)
                    )
                }
            )
        } else {
            segments = cueBuilder.segments(
                from: words,
                fallbackText: response.text,
                duration: response.duration
            )
            if words.isEmpty {
                warnings.append("OpenAI returned no timings; the transcript is one untimed segment.")
            }
        }

        let language = response.language ?? response.languages?.first?.code

        return TranscriptDocument(
            provider: CLIProvider.openai.rawValue,
            model: modelID.rawValue,
            sourceFile: file.path,
            text: response.text,
            language: language,
            duration: response.duration,
            segments: segments,
            words: words,
            warnings: warnings
        )
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
