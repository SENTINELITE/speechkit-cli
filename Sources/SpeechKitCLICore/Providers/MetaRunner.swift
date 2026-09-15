import Foundation
import SpeechKit

/// Transcribes files with Meta Muse Voice Transcribe.
public struct MetaRunner: ProviderRunner {
    /// The Meta provider.
    public static let provider: CLIProvider = .meta

    private let context: RunContext

    /// Creates a Meta runner.
    public init(context: RunContext) {
        self.context = context
    }

    /// Checks the model and language before any upload starts.
    ///
    /// - Throws: ``CLIError`` when `--model` or `--language` is not one Meta accepts.
    public func validate() throws {
        _ = try resolvedModelID()
        _ = try LanguageMapping.meta(context.languages)
    }

    /// Transcribes one file with Meta.
    public func transcribe(file: URL) async throws -> TranscriptDocument {
        let credential = try context.requireCredential(for: Self.provider)
        let modelID = try resolvedModelID()
        let languageBias = try LanguageMapping.meta(context.languages)
        var warnings: [String] = []

        if context.prompt != nil {
            warnings.append("Meta has no prompt parameter; --prompt was dropped.")
        }
        if context.wantsWords {
            warnings.append("Meta returns turns rather than words; --words produced no word timings.")
        }

        let mode: MetaTranscriptionMode = context.wantsDiarization ? .diarization : .endpointing
        let timeout = context.timeout ?? 10 * 60
        let configuration = MetaConfiguration(
            credential: credential,
            modelID: modelID,
            mode: mode,
            languageBias: languageBias,
            keywords: context.keywords,
            timeoutInterval: timeout,
            fileEndpoint: context.endpoint
        )
        let options = MetaFileTranscriptionOptions(
            modelID: modelID,
            mode: mode,
            languageBias: languageBias,
            keywords: context.keywords,
            timeoutInterval: timeout
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

    private func resolvedModelID() throws -> MetaModelID {
        guard let model = context.model else { return .museVoiceTranscribe1 }
        guard let modelID = MetaModelID(rawValue: model) else {
            throw CLIError.invalidModel(
                provider: .meta,
                model: model,
                valid: MetaModelID.allCases.map(\.rawValue)
            )
        }
        return modelID
    }

    @MainActor
    private static func send(
        file: URL,
        configuration: MetaConfiguration,
        options: MetaFileTranscriptionOptions
    ) async throws -> MetaFileTranscriptionResponse {
        let service = SpeechService(meta: configuration)
        return try await service.transcribeMetaAudioFile(file: file, options: options)
    }

    /// Maps a Meta response into a transcript document.
    ///
    /// Meta reports turn boundaries in milliseconds and never reports words, so
    /// segments come straight from `turns` and `words` stays empty.
    public static func map(
        _ response: MetaFileTranscriptionResponse,
        file: URL,
        modelID: MetaModelID,
        includeRaw: Bool = false,
        warnings: [String] = []
    ) -> TranscriptDocument {
        var warnings = warnings
        if includeRaw {
            warnings.append(rawUnavailableWarning)
        }

        let duration = response.audioDurationMs.map { Double($0) / 1000 }
        let turns = response.turns ?? []
        var segments = turns.map { turn in
            TranscriptDocument.Segment(
                start: Double(turn.startMs) / 1000,
                end: Double(turn.endMs) / 1000,
                text: turn.transcript.trimmingCharacters(in: .whitespacesAndNewlines),
                speaker: turn.speaker
            )
        }
        .filter { !$0.text.isEmpty }

        if segments.isEmpty {
            segments = SentenceSegmenter.segments(from: [], fallbackText: response.text, duration: duration)
            warnings.append("Meta returned no turns; the transcript is one untimed segment.")
        }

        return TranscriptDocument(
            provider: CLIProvider.meta.rawValue,
            model: modelID.rawValue,
            sourceFile: file.path,
            text: response.text,
            language: nil,
            duration: duration,
            segments: segments,
            words: [],
            warnings: warnings
        )
    }
}
