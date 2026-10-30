import Foundation
import SpeechKit

/// Transcribes files with Fish Audio Transcribe 1 Pro.
public struct FishAudioRunner: ProviderRunner {
    /// The Fish Audio provider.
    public static let provider: CLIProvider = .fishAudio

    /// How long one upload may take when `--timeout` is absent.
    ///
    /// Fish Audio answers only once the whole file is transcribed, and its docs
    /// suggest a 15-minute client timeout for long files.
    static let defaultTimeout: TimeInterval = 15 * 60

    private let context: RunContext

    /// Creates a Fish Audio runner.
    public init(context: RunContext) {
        self.context = context
    }

    /// Checks the model and language before any upload starts.
    ///
    /// - Throws: ``CLIError`` when `--model` or `--language` is not one Fish Audio accepts.
    public func validate() async throws {
        _ = try resolvedModelID()
        _ = try LanguageMapping.fishAudio(context.languages)
    }

    /// Transcribes one file with Fish Audio.
    public func transcribe(file: URL) async throws -> TranscriptDocument {
        let credential = try context.requireCredential(for: Self.provider)
        let modelID = try resolvedModelID()
        let language = try LanguageMapping.fishAudio(context.languages)
        var warnings = RunnerSupport.droppedOptionWarnings(
            prompt: context.prompt,
            keywords: context.keywords,
            for: Self.provider
        )
        if context.languages.count > 1, let language {
            warnings.append("Fish Audio takes one language hint; only \(language) was sent.")
        }

        let options = Self.options(
            modelID: modelID,
            language: language,
            wantsDiarization: context.wantsDiarization,
            timeout: context.timeout
        )
        let configuration = FishAudioConfiguration(
            credential: credential,
            fileTranscriptionModelID: modelID,
            language: language,
            timestamps: options.timestamps,
            diarize: options.diarize,
            timeoutInterval: options.timeoutInterval,
            fileEndpoint: context.endpoint
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

    /// Returns the request options for a run.
    ///
    /// Timestamps are always requested: Fish Audio's speaker turns, which
    /// become the segments, are empty without them, and the default sentence
    /// cues are built from its words. `--diarize` asks for speaker labels
    /// outright; without it Fish Audio decides for itself, because turning
    /// diarization off is not documented to keep the punctuated turns the
    /// words take their punctuation from.
    static func options(
        modelID: FishAudioFileTranscriptionModelID,
        language: String?,
        wantsDiarization: Bool,
        timeout: TimeInterval?
    ) -> FishAudioFileTranscriptionOptions {
        FishAudioFileTranscriptionOptions(
            modelID: modelID,
            language: language,
            timestamps: true,
            diarize: wantsDiarization ? .on : .auto,
            timeoutInterval: timeout ?? defaultTimeout
        )
    }

    private func resolvedModelID() throws -> FishAudioFileTranscriptionModelID {
        try RunnerSupport.resolveModel(context.model, default: .transcribe1Pro, provider: Self.provider)
    }

    @MainActor
    private static func send(
        file: URL,
        configuration: FishAudioConfiguration,
        options: FishAudioFileTranscriptionOptions
    ) async throws -> FishAudioFileTranscriptionResponse {
        let service = SpeechService(fishAudio: configuration)
        return try await service.transcribeFishAudioAudioFile(file: file, options: options)
    }

    /// Returns a Fish Audio speaker label in the CLI's form.
    ///
    /// Fish Audio labels speakers `speaker:0`, `speaker:1`, and so on. The
    /// prefix is dropped so the label reads `0` as Grok's does; formatters
    /// rename speakers `A`, `B` in order of appearance either way.
    static func speakerLabel(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let prefix = "speaker:"
        if trimmed.lowercased().hasPrefix(prefix) {
            let rest = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? nil : rest
        }
        return trimmed
    }

    /// Maps a Fish Audio response into a transcript document.
    ///
    /// Words come from SpeechKit's punctuated, speaker-labelled words, and
    /// segments from the speaker turns. When Fish Audio sends no timed turns,
    /// the segments are built from the words instead, and when it sends no
    /// words either, the transcript is one untimed segment.
    public static func map(
        _ response: FishAudioFileTranscriptionResponse,
        file: URL,
        modelID: FishAudioFileTranscriptionModelID,
        warnings: [String] = [],
        cueBuilder: CueBuilder = CueBuilder()
    ) -> TranscriptDocument {
        var warnings = warnings
        let text = response.transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)

        let words = response.words.map { word in
            TranscriptDocument.Word(
                text: word.text,
                start: word.start,
                end: word.end,
                speaker: speakerLabel(word.speaker)
            )
        }

        var segments = RunnerSupport.orderedSegments(
            response.speakerTurns.compactMap { turn -> TranscriptDocument.Segment? in
                guard let start = turn.start, let end = turn.end else { return nil }
                let turnText = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !turnText.isEmpty else { return nil }
                return TranscriptDocument.Segment(
                    start: start,
                    end: end,
                    text: turnText,
                    speaker: speakerLabel(turn.speaker)
                )
            }
        )

        if segments.isEmpty {
            segments = cueBuilder.segments(from: words, fallbackText: text, duration: response.duration)
            if words.isEmpty {
                warnings.append("Fish Audio returned no word timings; the transcript is one untimed segment.")
            }
        } else if words.isEmpty {
            warnings.append("Fish Audio returned no word timings; segments are its speaker turns.")
        }

        return TranscriptDocument(
            provider: CLIProvider.fishAudio.rawValue,
            model: modelID.rawValue,
            sourceFile: file.path,
            text: text,
            language: response.languageCode ?? response.language,
            duration: response.duration,
            segments: segments,
            words: words,
            warnings: warnings
        )
    }
}
