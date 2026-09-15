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
    public func validate() async throws {
        _ = try resolvedModelID()
        _ = LanguageMapping.gemini(context.languages)
    }

    /// Transcribes one file with Gemini.
    public func transcribe(file: URL) async throws -> TranscriptDocument {
        let credential = try context.requireCredential(for: Self.provider)
        let modelID = try resolvedModelID()
        let languageCodes = LanguageMapping.gemini(context.languages)
        var warnings = RunnerSupport.droppedOptionWarnings(prompt: context.prompt, for: Self.provider)

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
            warnings: warnings,
            cueBuilder: context.cueBuilder
        )
    }

    private func resolvedModelID() throws -> GeminiFileTranscriptionModelID {
        try RunnerSupport.resolveModel(context.model, default: .transcribe35, provider: Self.provider)
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
        warnings: [String] = [],
        cueBuilder: CueBuilder = CueBuilder()
    ) -> TranscriptDocument {
        var warnings = warnings

        let words = response.words.map { word in
            TranscriptDocument.Word(
                text: word.text,
                start: word.start,
                end: word.end,
                speaker: word.speaker
            )
        }

        let duration = words.compactMap { $0.end ?? $0.start }.max()
        let segments = cueBuilder.segments(
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
