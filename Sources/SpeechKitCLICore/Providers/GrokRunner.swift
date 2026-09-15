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

    /// Transcribes one file with Grok.
    public func transcribe(file: URL) async throws -> TranscriptDocument {
        let credential = try context.requireCredential(for: Self.provider)
        let modelID = try resolvedModelID()
        let language = try LanguageMapping.grok(context.languages)
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
        return Self.map(response, file: file, modelID: modelID, includeRaw: context.includeRaw)
    }

    private func resolvedModelID() throws -> GrokModelID {
        guard let model = context.model else { return .stt }
        guard let modelID = GrokModelID(rawValue: model) else {
            throw CLIError.invalidModel(
                provider: .grok,
                model: model,
                valid: GrokModelID.allCases.map(\.rawValue)
            )
        }
        return modelID
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
        includeRaw: Bool = false
    ) -> TranscriptDocument {
        var warnings: [String] = []
        if includeRaw {
            warnings.append(rawUnavailableWarning)
        }

        let words = (response.words ?? []).map { word in
            TranscriptDocument.Word(
                text: word.text,
                start: word.start,
                end: word.end,
                speaker: word.speaker.map(String.init)
            )
        }

        // TODO: phase 2 replaces this with CueBuilder, which also honours
        // gap, speaker change, and cue length limits.
        let segments = SentenceSegmenter.segments(from: words, fallbackText: response.text, duration: response.duration)
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
