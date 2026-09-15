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

    /// A renderer to draw on whatever standard error is, for tests.
    ///
    /// The real console decides for itself, from the terminal and the
    /// verbosity, and reaches for ``ProgressRenderer/shared``.
    private let renderer: ProgressRenderer?

    /// Creates a console.
    public init(verbosity: Verbosity = .normal) {
        self.verbosity = verbosity
        self.renderer = nil
    }

    /// Creates a console that always draws on a given renderer.
    init(verbosity: Verbosity, renderer: ProgressRenderer) {
        self.verbosity = verbosity
        self.renderer = renderer
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
        Console.writeAboveLiveArea("speechkit: \(message)\n")
    }

    /// Prints a warning to standard error unless `--quiet` was passed.
    public func warning(_ message: String) {
        guard verbosity != .quiet else { return }
        Console.writeAboveLiveArea("speechkit: warning: \(message)\n")
    }

    /// Prints a plain note to standard error unless `--quiet` was passed.
    ///
    /// Unlike ``progress(_:)`` this prints when standard error is a pipe, and
    /// unlike ``warning(_:)`` it carries no `warning:` label. It is for the
    /// things a run has to say whatever it is attached to, such as starting a
    /// several-hundred-megabyte model download.
    public func note(_ message: String) {
        guard verbosity != .quiet else { return }
        Console.writeAboveLiveArea("speechkit: " + message + "\n")
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
        Console.writeAboveLiveArea(message + "\n")
    }

    /// Prints detail to standard error only when `--verbose` was passed.
    public func verbose(_ message: String) {
        guard verbosity == .verbose else { return }
        Console.writeAboveLiveArea(message + "\n")
    }

    /// Starts one line of live progress.
    ///
    /// On a terminal the returned handle owns a row of the live area: it
    /// spins, it counts elapsed seconds, and it draws a bar once it is given a
    /// fraction. Through a pipe, and under `--quiet`, the handle draws nothing
    /// at all and its closing line goes out through ``progress(_:)`` or
    /// ``error(_:)``, so a redirected run writes the same bytes it always did.
    ///
    /// - Parameter label: What the task is doing, such as `talk.wav
    ///   transcribing`. Rows are truncated to the terminal width, so the most
    ///   identifying part belongs first.
    public func task(_ label: String) -> ProgressTask {
        guard let live = liveRenderer else {
            return ProgressTask(label: label, verbosity: verbosity)
        }
        let task = ProgressTask(label: label, renderer: live)
        // The handle is returned synchronously and registers itself a hop
        // later, so a caller can start a task and update it in the same
        // breath. `ProgressRenderer` keeps the two in order.
        Task { await task.push() }
        return task
    }

    /// The renderer live progress goes to, or `nil` when there is none.
    ///
    /// `--quiet` suppresses the live area outright, and a pipe has no cursor
    /// to move.
    private var liveRenderer: ProgressRenderer? {
        if let renderer { return renderer }
        guard verbosity != .quiet, isStandardErrorTTY else { return nil }
        return ProgressRenderer.shared
    }

    /// Writes text to standard output without a trailing newline.
    public func writeStandardOutput(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }

    /// Writes text to standard error without a trailing newline.
    public static func writeStandardError(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }

    /// Writes text to standard error, stepping over any live progress area.
    ///
    /// While a ``ProgressRenderer`` is drawing, the cursor rests at the first
    /// column of the first live row. Clearing from there and printing puts the
    /// message exactly where a piped run would have put it, and leaves the
    /// cursor at the top of what is now the live area, which the next frame
    /// redraws into. Without the clear, a warning and a spinner would share a
    /// row and neither would be readable.
    static func writeAboveLiveArea(_ text: String) {
        guard let renderer = ProgressLiveArea.current else {
            writeStandardError(text)
            return
        }
        writeStandardError(ProgressRenderer.clearBelow + text)
        Task { await renderer.redrawSoon() }
    }
}
