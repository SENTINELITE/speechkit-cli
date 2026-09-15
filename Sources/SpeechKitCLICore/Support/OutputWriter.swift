import Foundation

/// Decides where rendered transcripts go and writes them.
public struct OutputWriter: Sendable {
    /// One written or skipped output.
    public enum Destination: Sendable, Equatable {
        /// The text went to standard output.
        case standardOutput
        /// The text was written to a file.
        case file(URL)
        /// The file existed and `--overwrite` was not passed.
        case skipped(URL)
    }

    private let outputDirectory: URL?
    private let explicitOutput: URL?
    private let writesToStandardOutput: Bool
    private let overwrite: Bool
    private let console: Console

    /// Creates an output writer.
    public init(
        outputDirectory: URL?,
        explicitOutput: URL?,
        writesToStandardOutput: Bool,
        overwrite: Bool,
        console: Console
    ) {
        self.outputDirectory = outputDirectory
        self.explicitOutput = explicitOutput
        self.writesToStandardOutput = writesToStandardOutput
        self.overwrite = overwrite
        self.console = console
    }

    /// Returns the path a rendered transcript would be written to.
    public func destinationURL(for input: URL, fileExtension: String) -> URL {
        if let explicitOutput { return explicitOutput }
        let name = input.deletingPathExtension().lastPathComponent
        let directory = outputDirectory ?? input.deletingLastPathComponent()
        return directory.appendingPathComponent(name).appendingPathExtension(fileExtension)
    }

    /// Writes rendered text for one input file.
    ///
    /// - Throws: ``CLIError/writeFailed(_:reason:)`` when the file cannot be written.
    public func write(_ text: String, for input: URL, fileExtension: String) throws -> Destination {
        if writesToStandardOutput {
            console.writeStandardOutput(text)
            return .standardOutput
        }

        let url = destinationURL(for: input, fileExtension: fileExtension)
        let manager = FileManager.default
        if manager.fileExists(atPath: url.path), !overwrite {
            console.warning("\(url.path) exists; skipped. Pass --overwrite to replace it.")
            return .skipped(url)
        }

        do {
            let directory = url.deletingLastPathComponent()
            if !manager.fileExists(atPath: directory.path) {
                try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            throw CLIError.writeFailed(url, reason: error.localizedDescription)
        }
        return .file(url)
    }
}
