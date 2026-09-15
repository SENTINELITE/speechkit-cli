import Foundation

/// Renders a transcript as SubRip subtitles.
///
/// Cues are numbered from one, times use a comma before the milliseconds, and
/// cues are separated by a blank line. Output is UTF-8 with LF line endings and
/// no byte order mark. Speaker prefixes such as `[A] ` appear only when the
/// transcript was produced with `--diarize`.
public struct SRTFormatter: TranscriptFormatter {
    /// A Boolean value indicating whether `[A] ` speaker prefixes are written.
    public let showSpeakers: Bool

    /// The cue builder whose line width wraps the cue text.
    public let cueBuilder: CueBuilder

    /// The `srt` file extension.
    public let fileExtension = "srt"

    /// Creates a SubRip formatter.
    ///
    /// - Parameters:
    ///   - showSpeakers: Whether to prefix cues with a speaker label.
    ///   - cueBuilder: The builder that supplies the line width.
    public init(showSpeakers: Bool = false, cueBuilder: CueBuilder = CueBuilder()) {
        self.showSpeakers = showSpeakers
        self.cueBuilder = cueBuilder
    }

    /// Renders the document as SubRip subtitles.
    ///
    /// - Throws: ``CLIError/noTimingData(provider:)`` when the transcript has no
    ///   timed segments, because subtitles are never guessed.
    public func render(_ document: TranscriptDocument) throws -> String {
        guard document.hasTimings else {
            throw CLIError.noTimingData(provider: document.provider)
        }

        let labels = SpeakerLabels.labels(in: document.segments)
        var blocks: [String] = []

        for (index, segment) in document.segments.enumerated() {
            var text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if showSpeakers, let label = labels[index] {
                text = "[\(label)] \(text)"
            }
            let lines = cueBuilder.wrapLines(text)
            guard !lines.isEmpty else { continue }
            let timing = TimecodeFormatter.range(start: segment.start, end: segment.end, style: .srt)
            blocks.append("\(blocks.count + 1)\n\(timing)\n\(lines.joined(separator: "\n"))")
        }

        guard !blocks.isEmpty else {
            throw CLIError.noTimingData(provider: document.provider)
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }
}
