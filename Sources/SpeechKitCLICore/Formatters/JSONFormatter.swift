import Foundation

/// Renders a transcript as pretty-printed JSON with sorted keys.
public struct JSONFormatter: TranscriptFormatter {
    /// The `json` file extension.
    public let fileExtension = "json"

    /// Creates a JSON formatter.
    public init() {}

    /// Renders the document as JSON.
    ///
    /// - Throws: ``CLIError/writeFailed(_:reason:)`` when encoding fails.
    public func render(_ document: TranscriptDocument) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CLIError.usage("Failed to encode the transcript as UTF-8 JSON.")
        }
        return text + "\n"
    }
}
