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
    public func validate() throws {
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
        var warnings: [String] = []

        if context.timeout != nil {
            warnings.append("SpeechKit's Cohere client takes no request timeout; --timeout was dropped.")
        }
        if context.prompt != nil {
            warnings.append("Cohere has no prompt parameter; --prompt was dropped.")
        }
        if !context.keywords.isEmpty {
            warnings.append("Cohere has no vocabulary parameter; --keyword was dropped.")
        }

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
            includeRaw: context.includeRaw,
            warnings: warnings
        )
    }

    private func resolvedModelID() throws -> CohereModelID {
        guard let model = context.model else { return .transcribe032026 }
        guard let modelID = CohereModelID(rawValue: model) else {
            throw CLIError.invalidModel(
                provider: .cohere,
                model: model,
                valid: CohereModelID.allCases.map(\.rawValue)
            )
        }
        return modelID
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
        includeRaw: Bool = false,
        warnings: [String] = []
    ) -> TranscriptDocument {
        var warnings = warnings
        if includeRaw {
            warnings.append(rawUnavailableWarning)
        }
        warnings.append("Cohere returns text only; the transcript is one untimed segment.")

        return TranscriptDocument(
            provider: CLIProvider.cohere.rawValue,
            model: modelID.rawValue,
            sourceFile: file.path,
            text: text,
            language: nil,
            duration: nil,
            segments: SentenceSegmenter.segments(from: [], fallbackText: text, duration: nil),
            words: [],
            warnings: warnings
        )
    }
}
