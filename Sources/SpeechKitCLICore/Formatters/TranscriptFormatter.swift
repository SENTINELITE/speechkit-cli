import Foundation

/// Renders a ``TranscriptDocument`` into one output format.
public protocol TranscriptFormatter: Sendable {
    /// The file extension used when the tool names the output file.
    var fileExtension: String { get }

    /// Renders a transcript document.
    ///
    /// - Throws: ``CLIError`` when the document cannot be rendered in this format.
    func render(_ document: TranscriptDocument) throws -> String
}
