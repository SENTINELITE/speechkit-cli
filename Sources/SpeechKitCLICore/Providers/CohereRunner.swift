import Foundation
import SpeechKit

/// Transcribes files with Cohere Transcribe.
public struct CohereRunner: ProviderRunner {
    /// The Cohere provider.
    public static let provider: CLIProvider = .cohere

    private let context: RunContext

    /// Creates a Cohere runner.
    public init(context: RunContext) {
        self.context = context
    }

    /// Checks the model and language before any upload starts.
    ///
    /// - Throws: ``CLIError`` when `--model` or `--language` is not one Cohere accepts.
    public func validate() async throws {
        _ = try resolvedModelID()
        _ = try LanguageMapping.cohere(context.languages)
    }

    /// Transcribes one file with Cohere.
    ///
    /// SpeechKit has no detailed Cohere response type, so this goes through the
    /// `String`-returning facade and the document carries text only.
    public func transcribe(file: URL) async throws -> TranscriptDocument {
        let credential = try context.requireCredential(for: Self.provider)
        let modelID = try resolvedModelID()
        let language = try LanguageMapping.cohere(context.languages)
        let warnings = RunnerSupport.droppedOptionWarnings(
            prompt: context.prompt,
            keywords: context.keywords,
            timeout: context.timeout,
            for: Self.provider
        )

        let configuration = CohereConfiguration(
            credential: credential,
            modelID: modelID,
            language: language ?? .english,
            fileEndpoint: context.endpoint
        )
        let text = try await Self.send(
            file: file,
            configuration: configuration,
            options: .cohere(modelID: modelID, language: language, temperature: nil)
        )
        return Self.map(
            text,
            file: file,
            modelID: modelID,
            warnings: warnings
        )
    }

    private func resolvedModelID() throws -> CohereModelID {
        try RunnerSupport.resolveModel(context.model, default: .transcribe032026, provider: Self.provider)
    }

    @MainActor
    private static func send(
        file: URL,
        configuration: CohereConfiguration,
        options: SpeechFileTranscriptionOptions
    ) async throws -> String {
        let service = SpeechService(cohere: configuration)
        return try await service.transcribeAudioFile(provider: .cohere, file: file, options: options)
    }

    /// Maps Cohere transcript text into a transcript document.
    ///
    /// Cohere returns text only, so the document holds one untimed segment and
    /// no words. Subtitle formats reject it for that reason.
    public static func map(
        _ text: String,
        file: URL,
        modelID: CohereModelID,
        warnings: [String] = []
    ) -> TranscriptDocument {
        var warnings = warnings
        warnings.append("Cohere returns text only; the transcript is one untimed segment.")

        return TranscriptDocument(
            provider: CLIProvider.cohere.rawValue,
            model: modelID.rawValue,
            sourceFile: file.path,
            text: text,
            language: nil,
            duration: nil,
            segments: CueBuilder().segments(from: [], fallbackText: text, duration: nil),
            words: [],
            warnings: warnings
        )
    }
}
