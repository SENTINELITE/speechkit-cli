import Foundation
import SpeechKitVoz

/// Transcribes files with the on-device VOZ model.
///
/// VOZ needs no credential and sends no audio anywhere, but it does need a
/// model on disk. The runner prepares that model once in ``validate()``, before
/// any file is read, so a failed download exits with code 3 rather than failing
/// every file in turn.
///
/// This is a class rather than a struct because the whole batch shares one
/// prepared model, which the runner has to be able to release when the last
/// file finishes.
public final class VozRunner: ProviderRunner {
    /// The VOZ provider.
    public static let provider: CLIProvider = .voz

    /// The pinned model version reported in transcripts.
    public static let defaultModel = VozModelSession.modelVersion

    private let context: RunContext
    private let session: VozModelSession

    /// Creates a VOZ runner.
    public init(context: RunContext) {
        self.context = context
        self.session = VozModelSession()
    }

    /// Prepares the model before the first file is read.
    ///
    /// - Throws: ``CLIError/modelDownloadRefused(provider:size:)`` when the
    ///   model is missing and `--no-download` was passed, or
    ///   ``CLIError/modelNotReady(provider:reason:)`` when preparation fails.
    public func validate() async throws {
        try await session.ensureReady(
            console: context.console,
            allowsDownload: context.allowsModelDownload
        )
    }

    /// Transcribes one file with the prepared model.
    public func transcribe(file: URL) async throws -> TranscriptDocument {
        // A no-op once `validate()` has run, and the safety net for a caller
        // that built the runner directly.
        try await session.ensureReady(
            console: context.console,
            allowsDownload: context.allowsModelDownload
        )

        var warnings: [String] = []
        if context.model != nil {
            warnings.append("VOZ ships one pinned model version; --model is ignored.")
        }
        if context.endpoint != nil {
            warnings.append("VOZ runs on device; --endpoint is ignored.")
        }
        if !context.languages.isEmpty {
            warnings.append("VOZ takes no language hint; --language was ignored.")
        }
        warnings += RunnerSupport.droppedOptionWarnings(
            prompt: context.prompt,
            keywords: context.keywords,
            timeout: context.timeout,
            for: Self.provider
        )

        let response: VozFileTranscriptionResponse
        do {
            response = try await session.transcribe(file: file)
        } catch {
            throw CLIError.transcriptionFailed(
                file: file,
                reason: VozModelSession.message(for: error)
            )
        }

        let document = Self.map(
            response,
            file: file,
            warnings: warnings,
            cueBuilder: context.cueBuilder
        )
        // A timing note is detail, not a problem, so it goes through the
        // verbose channel rather than the warnings list.
        context.console.verbose(
            String(
                format: "%@: VOZ transcribed %.1f s of audio in %.1f s (%.1fx realtime).",
                file.lastPathComponent,
                response.duration,
                response.processingTime,
                response.realtimeFactor
            )
        )
        return document
    }

    /// Drops the in-memory model so the process exits promptly.
    public func finish() async {
        await session.release()
    }

    /// Maps a VOZ response into a transcript document.
    ///
    /// VOZ returns words and a full transcript, so segments come from the cue
    /// builder and obey the `--max-cue-*` limits. It reports no speaker, no
    /// confidence, and no language.
    public static func map(
        _ response: VozFileTranscriptionResponse,
        file: URL,
        warnings: [String] = [],
        cueBuilder: CueBuilder = CueBuilder()
    ) -> TranscriptDocument {
        let words = response.words.map { word in
            TranscriptDocument.Word(
                text: word.text,
                start: word.startTime,
                end: word.endTime
            )
        }
        let segments = RunnerSupport.orderedSegments(
            cueBuilder.segments(
                from: words,
                fallbackText: response.text,
                duration: response.duration
            )
        )

        return TranscriptDocument(
            provider: CLIProvider.voz.rawValue,
            model: defaultModel,
            sourceFile: file.path,
            text: response.text,
            language: nil,
            duration: response.duration,
            segments: segments,
            words: words,
            warnings: warnings,
            metrics: TranscriptDocument.Metrics(
                processingSeconds: response.processingTime
            ).nonEmpty
        )
    }
}
