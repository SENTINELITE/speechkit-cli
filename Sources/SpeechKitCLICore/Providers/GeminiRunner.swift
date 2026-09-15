import Foundation
import SpeechKit

/// Transcribes files with Google Gemini.
public struct GeminiRunner: ProviderRunner {
    /// The Gemini provider.
    public static let provider: CLIProvider = .gemini

    private let context: RunContext

    /// Creates a Gemini runner.
    public init(context: RunContext) {
        self.context = context
    }

    /// Checks the model and language before any upload starts.
    ///
    /// - Throws: ``CLIError`` when `--model` or `--language` is not one Gemini accepts.
    public func validate() throws {
        _ = try resolvedModelID()
        _ = LanguageMapping.gemini(context.languages)
    }

    /// Transcribes one file with Gemini.
    public func transcribe(file: URL) async throws -> TranscriptDocument {
        let credential = try context.requireCredential(for: Self.provider)
        let modelID = try resolvedModelID()
        let languageCodes = LanguageMapping.gemini(context.languages)
        var warnings: [String] = []

        if context.prompt != nil {
            warnings.append("Gemini has no prompt parameter; --prompt was dropped.")
        }

        // Gemini rejects a custom vocabulary combined with diarization or word
        // timestamps, so the keywords are dropped rather than failing the run.
        var customVocabulary = context.keywords
        if !customVocabulary.isEmpty, context.wantsDiarization || context.wantsWords {
            customVocabulary = []
            warnings.append("Gemini rejects --keyword with --diarize or --words; the keywords were dropped.")
        }

        let configuration = GeminiConfiguration(
            credential: credential,
            fileTranscriptionModelID: modelID,
            languageCodes: languageCodes,
            customVocabulary: customVocabulary,
            diarize: context.wantsDiarization,
            timestampGranularities: context.wantsWords ? [.word] : [],
            timeoutInterval: context.timeout ?? 10 * 60,
            fileEndpoint: context.endpoint
        )
        let options = GeminiFileTranscriptionOptions(
            modelID: modelID,
            languageCodes: languageCodes,
            customVocabulary: customVocabulary,
            diarize: context.wantsDiarization,
            timestampGranularities: context.wantsWords ? [.word] : [],
            timeoutInterval: context.timeout ?? 10 * 60
        )
        let response = try await Self.send(file: file, configuration: configuration, options: options)
        return Self.map(
            response,
            file: file,
            modelID: modelID,
            includeRaw: context.includeRaw,
            warnings: warnings
        )
    }

    private func resolvedModelID() throws -> GeminiFileTranscriptionModelID {
        guard let model = context.model else { return .transcribe35 }
        guard let modelID = GeminiFileTranscriptionModelID(rawValue: model) else {
            throw CLIError.invalidModel(
                provider: .gemini,
                model: model,
                valid: GeminiFileTranscriptionModelID.allCases.map(\.rawValue)
            )
        }
        return modelID
    }

    @MainActor
    private static func send(
        file: URL,
        configuration: GeminiConfiguration,
        options: GeminiFileTranscriptionOptions
    ) async throws -> GeminiFileTranscriptionResponse {
        let service = SpeechService(gemini: configuration)
        return try await service.transcribeGeminiAudioFile(file: file, options: options)
    }

    /// Maps a Gemini response into a transcript document.
    ///
    /// Gemini reports word offsets as optional duration strings, so a word
    /// without an end time keeps its start and leaves `end` empty for the cue
    /// builder to close.
    public static func map(
        _ response: GeminiFileTranscriptionResponse,
        file: URL,
        modelID: GeminiFileTranscriptionModelID,
        includeRaw: Bool = false,
        warnings: [String] = []
    ) -> TranscriptDocument {
        var warnings = warnings
        if includeRaw {
            warnings.append(rawUnavailableWarning)
        }

        let words = response.words.map { word in
            TranscriptDocument.Word(
                text: word.text,
                start: word.start,
                end: word.end,
                speaker: word.speaker
            )
        }

        let duration = words.compactMap { $0.end ?? $0.start }.max()
        let segments = SentenceSegmenter.segments(
            from: words,
            fallbackText: response.text,
            duration: duration
        )
        if words.isEmpty {
            warnings.append("Gemini returned no word timings; the transcript is one untimed segment.")
        }

        return TranscriptDocument(
            provider: CLIProvider.gemini.rawValue,
            model: modelID.rawValue,
            sourceFile: file.path,
            text: response.text,
            language: response.detectedLanguages?.first,
            duration: duration,
            segments: segments,
            words: words,
            warnings: warnings
        )
    }
}
