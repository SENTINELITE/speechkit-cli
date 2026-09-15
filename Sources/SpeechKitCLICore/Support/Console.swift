import Foundation

/// Writes progress, warnings, and errors to standard error.
///
/// Standard output carries transcripts only, so the tool stays pipeable.
public struct Console: Sendable {
    /// How much the tool prints to standard error.
    public enum Verbosity: Sendable, Equatable {
        /// Errors only.
        case quiet
        /// Errors and warnings.
        case normal
        /// Errors, warnings, and per-file progress.
        case verbose
    }

    /// The configured verbosity.
    public let verbosity: Verbosity

    /// Creates a console.
    public init(verbosity: Verbosity = .normal) {
        self.verbosity = verbosity
    }

    /// A Boolean value indicating whether standard error is a terminal.
    public var isStandardErrorTTY: Bool {
        isatty(FileHandle.standardError.fileDescriptor) == 1
    }

    /// A Boolean value indicating whether standard output is a terminal.
    public var isStandardOutputTTY: Bool {
        isatty(FileHandle.standardOutput.fileDescriptor) == 1
    }

    /// Prints an error to standard error.
    public func error(_ message: String) {
        Console.writeStandardError("speechkit: \(message)\n")
    }

    /// Prints a warning to standard error unless `--quiet` was passed.
    public func warning(_ message: String) {
        guard verbosity != .quiet else { return }
        Console.writeStandardError("speechkit: warning: \(message)\n")
    }

    /// Prints progress to standard error when attached to a terminal or when `--verbose` was passed.
    public func progress(_ message: String) {
        switch verbosity {
        case .quiet:
            return
        case .normal:
            guard isStandardErrorTTY else { return }
        case .verbose:
            break
        }
        Console.writeStandardError(message + "\n")
    }

    /// Prints detail to standard error only when `--verbose` was passed.
    public func verbose(_ message: String) {
        guard verbosity == .verbose else { return }
        Console.writeStandardError(message + "\n")
    }

    /// Writes text to standard output without a trailing newline.
    public func writeStandardOutput(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }

    /// Writes text to standard error without a trailing newline.
    public static func writeStandardError(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }
}
