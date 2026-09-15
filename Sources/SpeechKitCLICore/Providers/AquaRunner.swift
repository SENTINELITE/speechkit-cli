import Foundation
import SpeechKit

/// Transcribes files with Aqua Voice.
public struct AquaRunner: ProviderRunner {
    /// The Aqua provider.
    public static let provider: CLIProvider = .aqua

    private let context: RunContext

    /// Creates an Aqua runner.
    public init(context: RunContext) {
        self.context = context
    }

    /// Checks the model and language before any upload starts.
    ///
    /// - Throws: ``CLIError`` when `--model` or `--language` is not one Aqua accepts.
    public func validate() async throws {
        _ = try resolvedModelID()
        _ = try LanguageMapping.aqua(context.languages)
    }

    /// Transcribes one file with Aqua.
    public func transcribe(file: URL) async throws -> TranscriptDocument {
        let credential = try context.requireCredential(for: Self.provider)
        let modelID = try resolvedModelID()
        let language = try LanguageMapping.aqua(context.languages)
        let warnings = RunnerSupport.droppedOptionWarnings(
            prompt: context.prompt,
            keywords: context.keywords,
            timeout: context.timeout,
            for: Self.provider
        )

        let configuration = AquaConfiguration(
            credential: credential,
            modelID: modelID,
            language: language,
            fileEndpoint: context.endpoint
        )
        let options = AquaFileTranscriptionOptions(modelID: modelID, language: language)
        let response = try await Self.send(file: file, configuration: configuration, options: options)
        return Self.map(
            response,
            file: file,
            modelID: modelID,
            warnings: warnings
        )
    }

    private func resolvedModelID() throws -> AquaModelID {
        try RunnerSupport.resolveModel(context.model, default: .avalonV15, provider: Self.provider)
    }

    @MainActor
    private static func send(
        file: URL,
        configuration: AquaConfiguration,
        options: AquaFileTranscriptionOptions
    ) async throws -> AquaFileTranscriptionResponse {
        let service = SpeechService(aqua: configuration)
        return try await service.transcribeAquaAudioFile(file: file, options: options)
    }

    /// Maps an Aqua response into a transcript document.
    ///
    /// Aqua returns text and billing usage only, so the document holds one
    /// untimed segment and no words. Subtitle formats reject it for that reason.
    public static func map(
        _ response: AquaFileTranscriptionResponse,
        file: URL,
        modelID: AquaModelID,
        warnings: [String] = []
    ) -> TranscriptDocument {
        var warnings = warnings
        warnings.append("Aqua returns text only; the transcript is one untimed segment.")

        return TranscriptDocument(
            provider: CLIProvider.aqua.rawValue,
            model: modelID.rawValue,
            sourceFile: file.path,
            text: response.text,
            language: nil,
            duration: nil,
            segments: CueBuilder().segments(from: [], fallbackText: response.text, duration: nil),
            words: [],
            warnings: warnings,
            metrics: TranscriptDocument.Metrics(billedSeconds: response.usage.seconds).nonEmpty
        )
    }
}
