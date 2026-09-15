import Foundation
import SpeechKit

/// Transcribes files with xAI Grok.
public struct GrokRunner: ProviderRunner {
    /// The Grok provider.
    public static let provider: CLIProvider = .grok

    private let context: RunContext

    /// Creates a Grok runner.
    public init(context: RunContext) {
        self.context = context
    }

    /// Checks the model and language before any upload starts.
    ///
    /// - Throws: ``CLIError`` when `--model` or `--language` is not one Grok accepts.
    public func validate() async throws {
        _ = try resolvedModelID()
        _ = try LanguageMapping.grok(context.languages)
    }

    /// Transcribes one file with Grok.
    public func transcribe(file: URL) async throws -> TranscriptDocument {
        let credential = try context.requireCredential(for: Self.provider)
        let modelID = try resolvedModelID()
        let language = try LanguageMapping.grok(context.languages)
        let warnings = RunnerSupport.droppedOptionWarnings(
            prompt: context.prompt,
            keywords: context.keywords,
            for: Self.provider
        )
        let configuration = GrokConfiguration(
            credential: credential,
            modelID: modelID,
            language: language,
            diarize: context.wantsDiarization,
            timestampGranularities: context.wantsWords ? [.word] : [],
            timeoutInterval: context.timeout ?? 10 * 60,
            fileEndpoint: context.endpoint
        )
        let response = try await Self.send(file: file, configuration: configuration)
        return Self.map(
            response,
            file: file,
            modelID: modelID,
            warnings: warnings,
            cueBuilder: context.cueBuilder
        )
    }

    private func resolvedModelID() throws -> GrokModelID {
        try RunnerSupport.resolveModel(context.model, default: .stt, provider: Self.provider)
    }

    @MainActor
    private static func send(
        file: URL,
        configuration: GrokConfiguration
    ) async throws -> GrokFileTranscriptionResponse {
        let service = SpeechService(grok: configuration)
        return try await service.transcribeGrokAudioFile(file: file)
    }

    /// Maps a Grok response into a transcript document.
    public static func map(
        _ response: GrokFileTranscriptionResponse,
        file: URL,
        modelID: GrokModelID,
        warnings: [String] = [],
        cueBuilder: CueBuilder = CueBuilder()
    ) -> TranscriptDocument {
        var warnings = warnings

        let words = (response.words ?? []).map { word in
            TranscriptDocument.Word(
                text: word.text,
                start: word.start,
                end: word.end,
                speaker: word.speaker.map(String.init)
            )
        }

        let segments = cueBuilder.segments(
            from: words,
            fallbackText: response.text,
            duration: response.duration
        )
        if words.isEmpty {
            warnings.append("Grok returned no word timings; the transcript is one untimed segment.")
        }

        return TranscriptDocument(
            provider: CLIProvider.grok.rawValue,
            model: modelID.rawValue,
            sourceFile: file.path,
            text: response.text,
            language: response.language,
            duration: response.duration,
            segments: segments,
            words: words,
            warnings: warnings
        )
    }
}
