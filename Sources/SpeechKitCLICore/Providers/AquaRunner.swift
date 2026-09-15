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
    public func validate() throws {
        _ = try resolvedModelID()
        _ = try LanguageMapping.aqua(context.languages)
    }

    /// Transcribes one file with Aqua.
    public func transcribe(file: URL) async throws -> TranscriptDocument {
        let credential = try context.requireCredential(for: Self.provider)
        let modelID = try resolvedModelID()
        let language = try LanguageMapping.aqua(context.languages)
        var warnings: [String] = []

        if context.prompt != nil {
            warnings.append("Aqua has no prompt parameter; --prompt was dropped.")
        }
        if !context.keywords.isEmpty {
            warnings.append("Aqua has no vocabulary parameter; --keyword was dropped.")
        }

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
            includeRaw: context.includeRaw,
            warnings: warnings
        )
    }

    private func resolvedModelID() throws -> AquaModelID {
        guard let model = context.model else { return .avalonV15 }
        guard let modelID = AquaModelID(rawValue: model) else {
            throw CLIError.invalidModel(
                provider: .aqua,
                model: model,
                valid: AquaModelID.allCases.map(\.rawValue)
            )
        }
        return modelID
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
        includeRaw: Bool = false,
        warnings: [String] = []
    ) -> TranscriptDocument {
        var warnings = warnings
        if includeRaw {
            warnings.append(rawUnavailableWarning)
        }
        warnings.append("Aqua returns text only; the transcript is one untimed segment.")

        return TranscriptDocument(
            provider: CLIProvider.aqua.rawValue,
            model: modelID.rawValue,
            sourceFile: file.path,
            text: response.text,
            language: nil,
            duration: nil,
            segments: SentenceSegmenter.segments(from: [], fallbackText: response.text, duration: nil),
            words: [],
            warnings: warnings
        )
    }
}
