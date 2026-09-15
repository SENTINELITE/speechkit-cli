import Foundation
import Speech
import SpeechKit

/// Transcribes files with Apple's local Speech framework.
///
/// Apple transcription runs on device and needs no credential, but it requires
/// macOS 26 or later.
@available(macOS 26.0, *)
public struct AppleRunner: ProviderRunner {
    /// The Apple provider.
    public static let provider: CLIProvider = .apple

    private let context: RunContext

    /// Creates an Apple runner.
    public init(context: RunContext) {
        self.context = context
    }

    /// Checks `--language` against the locales this machine's transcriber supports.
    ///
    /// The Speech framework reports its locales asynchronously, because the list
    /// depends on assets the system may still be downloading, so this is the one
    /// runner whose validation has to await something.
    ///
    /// - Throws: ``CLIError/usage(_:)`` when the locale is not supported here.
    public func validate() async throws {
        guard let requested = LanguageMapping.apple(context.languages) else { return }
        let supported = await SpeechTranscriber.supportedLocales
        guard !supported.isEmpty else { return }
        guard !Self.isSupported(requested, in: supported) else { return }

        let examples = supported
            .map { $0.identifier(.bcp47) }
            .sorted()
            .prefix(3)
            .joined(separator: ", ")
        throw CLIError.usage(
            "\(requested.identifier(.bcp47)) is not a locale this machine's transcriber supports. Supported identifiers include \(examples). Run 'speechkit languages apple' for the full list."
        )
    }

    /// Returns whether a requested locale matches one the transcriber supports.
    ///
    /// A bare language such as `en` matches any region of it, so `--language en`
    /// keeps working on a machine that lists `en-US` alone.
    static func isSupported(_ requested: Locale, in supported: some Collection<Locale>) -> Bool {
        let tag = requested.identifier(.bcp47).lowercased()
        if supported.contains(where: { $0.identifier(.bcp47).lowercased() == tag }) { return true }
        guard requested.region == nil, let language = requested.language.languageCode?.identifier.lowercased() else {
            return false
        }
        return supported.contains { $0.language.languageCode?.identifier.lowercased() == language }
    }

    /// Transcribes one file with Apple's local Speech framework.
    public func transcribe(file: URL) async throws -> TranscriptDocument {
        var warnings: [String] = []
        if context.model != nil {
            warnings.append("Apple local transcription has no model identifier; --model is ignored.")
        }
        if context.endpoint != nil {
            warnings.append("Apple local transcription runs on device; --endpoint is ignored.")
        }
        if context.timeout != nil {
            warnings.append("Apple local transcription has no request timeout; --timeout is ignored.")
        }
        if context.prompt != nil {
            warnings.append("Apple local transcription takes no prompt; --prompt is ignored.")
        }

        let locale = LanguageMapping.apple(context.languages) ?? .current
        let configuration = AppleSpeechConfiguration(
            locale: locale,
            contextualStrings: context.keywords
        )
        let response = try await Self.send(file: file, configuration: configuration)
        return Self.map(
            response,
            file: file,
            warnings: warnings,
            cueBuilder: context.cueBuilder
        )
    }

    @MainActor
    private static func send(
        file: URL,
        configuration: AppleSpeechConfiguration
    ) async throws -> AppleSpeechFileTranscriptionResponse {
        let service = SpeechService(apple: configuration)
        return try await service.transcribeAppleAudioFile(file: file)
    }

    /// Maps an Apple response into a transcript document.
    public static func map(
        _ response: AppleSpeechFileTranscriptionResponse,
        file: URL,
        warnings: [String] = [],
        cueBuilder: CueBuilder = CueBuilder()
    ) -> TranscriptDocument {
        let warnings = warnings

        // Apple does not diarize. SpeechKit fills `speaker` on Apple entries with
        // the locale identifier, so the runner drops it rather than pass a
        // locale off as a speaker label.
        let words = response.entries.flatMap { entry in
            entry.words.map { word in
                TranscriptDocument.Word(
                    text: word.text,
                    start: word.start,
                    end: word.end,
                    speaker: nil,
                    confidence: word.confidence
                )
            }
        }

        // Apple's entries are analyser chunks rather than readable cues: one
        // sentence can arrive as half a dozen entries, and a long pause can
        // arrive as one. When every entry carries word timings the cue builder
        // regroups the words into cues that obey the command line limits, which
        // is what the subtitle formats need. Otherwise the entries stand as
        // they came.
        let entrySegments = RunnerSupport.orderedSegments(
            response.entries.compactMap { entry -> TranscriptDocument.Segment? in
                let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                let start = entry.start ?? 0
                return TranscriptDocument.Segment(
                    start: start,
                    end: start + (entry.duration ?? 0),
                    text: text,
                    speaker: nil
                )
            }
        )
        let hasWordTimings = !words.isEmpty && words.allSatisfy { $0.start != nil }
        let segments = hasWordTimings
            ? cueBuilder.segments(from: words, fallbackText: response.text, duration: nil)
            : entrySegments

        let duration = segments.map(\.end).max()

        return TranscriptDocument(
            provider: CLIProvider.apple.rawValue,
            model: nil,
            sourceFile: file.path,
            text: response.text,
            language: response.locale.identifier(.bcp47),
            duration: duration,
            segments: segments,
            words: words,
            warnings: warnings
        )
    }
}
