import Foundation
import SpeechKit

/// Transcribes files with ElevenLabs Scribe.
public struct ElevenLabsRunner: ProviderRunner {
    /// The ElevenLabs provider.
    public static let provider: CLIProvider = .elevenlabs

    /// The models ElevenLabs accepts for file transcription.
    ///
    /// The realtime Scribe model is rejected by the upload endpoint, so it is
    /// not offered here.
    public static let fileModelIDs: [ElevenLabsModelID] = [.scribeV1, .scribeV2]

    /// The token types ElevenLabs uses for whitespace between words.
    private static let spacingTypes: Set<String> = ["spacing", "space"]

    private let context: RunContext

    /// Creates an ElevenLabs runner.
    public init(context: RunContext) {
        self.context = context
    }

    /// Checks the model before any upload starts.
    ///
    /// - Throws: ``CLIError`` when `--model` is not an ElevenLabs file model.
    public func validate() throws {
        _ = try resolvedModelID()
    }

    /// Transcribes one file with ElevenLabs.
    public func transcribe(file: URL) async throws -> TranscriptDocument {
        let credential = try context.requireCredential(for: Self.provider)
        let modelID = try resolvedModelID()
        var warnings: [String] = []

        if !context.languages.isEmpty {
            warnings.append("ElevenLabs Scribe detects the language itself; --language was ignored.")
        }
        if context.timeout != nil {
            warnings.append("SpeechKit's ElevenLabs client takes no request timeout; --timeout was dropped.")
        }
        if context.prompt != nil {
            warnings.append("ElevenLabs has no prompt parameter; --prompt was dropped.")
        }
        if !context.keywords.isEmpty {
            warnings.append("ElevenLabs has no vocabulary parameter; --keyword was dropped.")
        }

        let configuration = ElevenLabsConfiguration(
            credential: credential,
            fileTranscriptionModelID: modelID,
            fileEndpoint: context.endpoint
        )
        let response = try await Self.send(file: file, configuration: configuration, modelID: modelID)
        return Self.map(
            response,
            file: file,
            modelID: modelID,
            includeRaw: context.includeRaw,
            warnings: warnings
        )
    }

    private func resolvedModelID() throws -> ElevenLabsModelID {
        guard let model = context.model else { return .scribeV1 }
        guard let modelID = ElevenLabsModelID(rawValue: model), Self.fileModelIDs.contains(modelID) else {
            throw CLIError.invalidModel(
                provider: .elevenlabs,
                model: model,
                valid: Self.fileModelIDs.map(\.rawValue)
            )
        }
        return modelID
    }

    @MainActor
    private static func send(
        file: URL,
        configuration: ElevenLabsConfiguration,
        modelID: ElevenLabsModelID
    ) async throws -> ElevenLabsFileTranscriptionResponse {
        let service = SpeechService(elevenLabs: configuration)
        return try await service.transcribeElevenLabsAudioFile(file: file, modelID: modelID)
    }

    /// Maps an ElevenLabs response into a transcript document.
    ///
    /// Scribe interleaves spacing tokens with words. Those carry timings but no
    /// text worth keeping, so they are dropped before words and segments are built.
    public static func map(
        _ response: ElevenLabsFileTranscriptionResponse,
        file: URL,
        modelID: ElevenLabsModelID,
        includeRaw: Bool = false,
        warnings: [String] = []
    ) -> TranscriptDocument {
        var warnings = warnings
        if includeRaw {
            warnings.append(rawUnavailableWarning)
        }

        let tokens = response.words ?? []
        let words = tokens
            .filter { !spacingTypes.contains($0.type.lowercased()) }
            .map { token in
                TranscriptDocument.Word(
                    text: token.text,
                    start: token.start,
                    end: token.end,
                    confidence: token.logprob
                )
            }
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }

        let duration = tokens.map(\.end).max()
        let segments = SentenceSegmenter.segments(
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
