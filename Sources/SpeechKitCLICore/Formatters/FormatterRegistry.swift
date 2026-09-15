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
    ///   - cueBuilder: The builder whose line width wraps subtitle text.
    /// - Throws: ``CLIError`` when a format cannot be served.
    public static func makeFormatter(
        for format: OutputFormat,
        includesSpeakerLabels: Bool = false,
        includesWordTimings: Bool = false,
        cueBuilder: CueBuilder = CueBuilder()
    ) throws -> any TranscriptFormatter {
        switch format {
        case .txt:
            return PlainTextFormatter(includesSpeakerLabels: includesSpeakerLabels)
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
