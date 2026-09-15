import Foundation

/// Maps an ``OutputFormat`` to the formatter that renders it.
///
/// This switch is the only place formats are wired to formatters, so later
/// phases add SRT and VTT here and nowhere else.
public enum FormatterRegistry {
    /// Returns the formatter for a format.
    ///
    /// - Parameters:
    ///   - format: The requested output format.
    ///   - includesSpeakerLabels: Whether the output should carry speaker labels.
    /// - Throws: ``CLIError/notImplemented(_:)`` for formats a later phase adds.
    public static func makeFormatter(
        for format: OutputFormat,
        includesSpeakerLabels: Bool = false
    ) throws -> any TranscriptFormatter {
        switch format {
        case .txt:
            return PlainTextFormatter(includesSpeakerLabels: includesSpeakerLabels)
        case .json:
            return JSONFormatter()
        case .srt:
            throw CLIError.notImplemented("--format srt")
        case .vtt:
            throw CLIError.notImplemented("--format vtt")
        }
    }
}
