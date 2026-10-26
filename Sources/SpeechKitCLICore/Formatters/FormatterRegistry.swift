import Foundation

/// Maps an ``OutputFormat`` to the formatter that renders it.
///
/// This switch is the only place formats are wired to formatters.
public enum FormatterRegistry {
    /// Returns the formatter for a format.
    ///
    /// - Parameters:
    ///   - format: The requested output format.
    ///   - includesSpeakerLabels: Whether the output should carry speaker labels.
    ///   - includesWordTimings: Whether WebVTT cues should carry inline word timing tags.
    ///   - includesTimestamps: Whether plain text is written one timestamped sentence per line.
    ///   - cueBuilder: The builder whose line width wraps subtitle text and
    ///     whose sentence rules split plain text.
    /// - Throws: ``CLIError`` when a format cannot be served.
    public static func makeFormatter(
        for format: OutputFormat,
        includesSpeakerLabels: Bool = false,
        includesWordTimings: Bool = false,
        includesTimestamps: Bool = false,
        cueBuilder: CueBuilder = CueBuilder()
    ) throws -> any TranscriptFormatter {
        switch format {
        case .txt:
            return PlainTextFormatter(
                includesSpeakerLabels: includesSpeakerLabels,
                includesTimestamps: includesTimestamps,
                cueBuilder: cueBuilder
            )
        case .json:
            return JSONFormatter()
        case .srt:
            return SRTFormatter(showSpeakers: includesSpeakerLabels, cueBuilder: cueBuilder)
        case .vtt:
            return VTTFormatter(
                showSpeakers: includesSpeakerLabels,
                showWordTimings: includesWordTimings,
                cueBuilder: cueBuilder
            )
        }
    }
}
