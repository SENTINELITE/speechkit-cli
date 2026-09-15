import Foundation
import SpeechKit

/// Transcribes files with OpenAI.
public struct OpenAIRunner: ProviderRunner {
    /// The OpenAI provider.
    public static let provider: CLIProvider = .openai

    private let context: RunContext

    /// Creates an OpenAI runner.
    public init(context: RunContext) {
        self.context = context
    }

    /// Transcribes one file with OpenAI.
    public func transcribe(file: URL) async throws -> TranscriptDocument {
        let credential = try context.requireCredential(for: Self.provider)
        let modelID = try resolvedModelID()
        let languages = LanguageMapping.openAI(context.languages)
        let configuration = OpenAIConfiguration(
            credential: credential,
            fileTranscriptionModelID: modelID,
            language: languages.language,
            languages: languages.languages,
            prompt: context.prompt,
            keywords: context.keywords,
            diarizationChunkingStrategy: context.wantsDiarization ? .auto : nil,
            timeoutInterval: context.timeout ?? 10 * 60,
            fileEndpoint: context.endpoint
        )
        let options = OpenAIFileTranscriptionOptions(
            modelID: modelID,
            language: languages.language,
            languages: languages.languages,
            prompt: context.prompt,
            keywords: context.keywords,
            timestampGranularities: context.wantsWords ? [.word, .segment] : [],
            diarizationChunkingStrategy: context.wantsDiarization ? .auto : nil,
            timeoutInterval: context.timeout ?? 10 * 60
        )
        let response = try await Self.send(file: file, configuration: configuration, options: options)
        return Self.map(
            response,
            file: file,
            modelID: modelID,
            includeRaw: context.includeRaw,
            cueBuilder: context.cueBuilder
        )
    }

    private func resolvedModelID() throws -> OpenAIFileTranscriptionModelID {
        guard let model = context.model else {
            return context.wantsDiarization ? .gpt4oTranscribeDiarize : .gptTranscribe
        }
        guard let modelID = OpenAIFileTranscriptionModelID(rawValue: model) else {
            throw CLIError.invalidModel(
                provider: .openai,
                model: model,
                valid: OpenAIFileTranscriptionModelID.allCases.map(\.rawValue)
            )
        }
        return modelID
    }

    @MainActor
    private static func send(
        file: URL,
        configuration: OpenAIConfiguration,
        options: OpenAIFileTranscriptionOptions
    ) async throws -> OpenAIFileTranscriptionResponse {
        let service = SpeechService(openAI: configuration)
        return try await service.transcribeOpenAIAudioFile(file: file, options: options)
    }

    /// Maps an OpenAI response into a transcript document.
    public static func map(
        _ response: OpenAIFileTranscriptionResponse,
        file: URL,
        modelID: OpenAIFileTranscriptionModelID,
        includeRaw: Bool = false,
        cueBuilder: CueBuilder = CueBuilder()
    ) -> TranscriptDocument {
        var warnings: [String] = []
        if includeRaw {
            warnings.append(rawUnavailableWarning)
        }

        let words = (response.words ?? []).map { word in
            TranscriptDocument.Word(text: word.word, start: word.start, end: word.end)
        }

        var segments: [TranscriptDocument.Segment] = []
        if let diarized = response.diarizedSegments, !diarized.isEmpty {
            segments = diarized.map { segment in
                TranscriptDocument.Segment(
                    start: segment.start ?? 0,
                    end: segment.end ?? segment.start ?? 0,
                    text: normalized(segment.text),
                    speaker: segment.speaker
                )
            }
        } else if let plain = response.segments, !plain.isEmpty {
            segments = plain.map { segment in
                TranscriptDocument.Segment(
                    start: segment.start ?? 0,
                    end: segment.end ?? segment.start ?? 0,
                    text: normalized(segment.text)
                )
            }
        } else {
            segments = cueBuilder.segments(
                from: words,
                fallbackText: response.text,
                duration: response.duration
            )
            if words.isEmpty {
                warnings.append("OpenAI returned no timings; the transcript is one untimed segment.")
            }
        }

        let language = response.language ?? response.languages?.first?.code

        return TranscriptDocument(
            provider: CLIProvider.openai.rawValue,
            model: modelID.rawValue,
            sourceFile: file.path,
            text: response.text,
            language: language,
            duration: response.duration,
            segments: segments,
            words: words,
            warnings: warnings
        )
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
