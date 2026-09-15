import Darwin
import Foundation
import Testing
@testable import SpeechKitCLICore

/// Collects the bytes a renderer writes, so escape sequences can be asserted.
private final class RecordingOutput: ProgressOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var chunks: [String] = []

    func write(_ text: String) {
        lock.withLock { chunks.append(text) }
    }

    /// Everything written so far, in order.
    var text: String {
        lock.withLock { chunks.joined() }
    }
}

@Suite("Progress renderer")
struct ProgressRendererTests {
    private let hide = ProgressRenderer.hideCursor
    private let show = ProgressRenderer.showCursor
    private let clear = ProgressRenderer.clearBelow

    // MARK: - Frame bytes

    @Test("A first frame hides the cursor, clears below, and leaves the cursor on the first row")
    func frameBytes() {
        let frame = ProgressRenderer.frame(lines: ["one", "two", "three"], hidesCursor: true)
        #expect(frame == "\u{1B}[?25l\u{1B}[0J" + "one\ntwo\nthree" + "\u{1B}[2A" + "\r")
    }

    @Test("A later frame does not hide the cursor again, and one row needs no cursor move")
    func laterFrameBytes() {
        let frame = ProgressRenderer.frame(lines: ["one"], hidesCursor: false)
        #expect(frame == "\u{1B}[0J" + "one" + "\r")
    }

    @Test("A live task draws a spinner, its label, and its elapsed time")
    func firstFrame() async {
        let sink = RecordingOutput()
        let renderer = ProgressRenderer(output: sink, width: 60)
        let task = ProgressTask(label: "talk.wav transcribing", renderer: renderer)
        await task.push()
        #expect(sink.text == hide + clear + "⠋ talk.wav transcribing 0:00" + "\r")
    }

    @Test("Two tasks draw two rows in the order they started")
    func twoRows() async {
        let sink = RecordingOutput()
        let renderer = ProgressRenderer(output: sink, width: 60)
        let first = ProgressTask(label: "a.wav transcribing", renderer: renderer)
        let second = ProgressTask(label: "b.wav transcribing", renderer: renderer)
        await first.push()
        await second.push()
        await first.update(label: "a.wav writing")
        await renderer.drawImmediately()
        #expect(sink.text.hasSuffix("⠋ a.wav writing 0:00\n⠋ b.wav transcribing 0:00\u{1B}[1A\r"))
    }

    // MARK: - Collapsing

    @Test("A finished task clears the live area, prints its line, and redraws what is left")
    func finishCollapsesAbove() async {
        let sink = RecordingOutput()
        let renderer = ProgressRenderer(output: sink, width: 60)
        let first = ProgressTask(label: "a.wav transcribing", renderer: renderer)
        let second = ProgressTask(label: "b.wav transcribing", renderer: renderer)
        await first.push()
        await second.push()

        await first.finish(line: "[1/2] a.wav -> a.txt (voz, 1.2 s)")
        let text = sink.text
        // The line lands where the rows were, so scrollback reads like a piped
        // run, and the one remaining row is drawn again under it.
        #expect(text.contains(clear + "[1/2] a.wav -> a.txt (voz, 1.2 s)\n"))
        #expect(text.hasSuffix(clear + "⠙ b.wav transcribing 0:00\r"))
    }

    @Test("A failed task prints its line the way an error is printed")
    func failPrintsError() async {
        let sink = RecordingOutput()
        let renderer = ProgressRenderer(output: sink, width: 60)
        let task = ProgressTask(label: "a.wav transcribing", renderer: renderer)
        await task.push()
        await task.fail(line: "a.wav: the provider refused the file.")
        #expect(sink.text.contains(clear + "speechkit: a.wav: the provider refused the file.\n"))
    }

    @Test("The last task to finish restores the cursor and leaves no live area")
    func lastFinishRestoresCursor() async {
        let sink = RecordingOutput()
        let renderer = ProgressRenderer(output: sink, width: 60)
        let task = ProgressTask(label: "a.wav transcribing", renderer: renderer)
        await task.push()
        await task.finish(line: "[1/1] a.wav -> a.txt (voz, 1.2 s)")
        #expect(sink.text.hasSuffix(clear + show))
    }

    @Test("A task that finished cannot be redrawn by a late update")
    func lateUpdateIsIgnored() async {
        let sink = RecordingOutput()
        let renderer = ProgressRenderer(output: sink, width: 60)
        let task = ProgressTask(label: "a.wav transcribing", renderer: renderer)
        await task.push()
        await task.finish()
        let afterFinish = sink.text
        await task.update(label: "a.wav writing")
        #expect(sink.text == afterFinish)
    }

    // MARK: - Line composition

    @Test("A row is truncated to the terminal width, with an ellipsis where it was cut")
    func truncatesToWidth() async {
        let label = String(repeating: "long-file-name-", count: 6)
        let line = ProgressRenderer.line(
            spinner: "⠋",
            label: label,
            fraction: nil,
            elapsed: 5,
            width: 40
        )
        #expect(line.count == 40)
        #expect(line.hasPrefix("⠋ long-file-name-"))
        #expect(line.hasSuffix("…"))
    }

    @Test("A row that fits is not touched")
    func doesNotTruncateShortLines() {
        let line = ProgressRenderer.line(spinner: "⠋", label: "voz: ready", fraction: nil, elapsed: 5, width: 40)
        #expect(line == "⠋ voz: ready 0:05")
    }

    @Test("A renderer with a width truncates the rows it draws")
    func rendererTruncates() async {
        let sink = RecordingOutput()
        let renderer = ProgressRenderer(output: sink, width: 40)
        let task = ProgressTask(label: String(repeating: "x", count: 80), renderer: renderer)
        await task.push()
        let row = sink.text
            .replacingOccurrences(of: hide, with: "")
            .replacingOccurrences(of: clear, with: "")
            .replacingOccurrences(of: "\r", with: "")
        #expect(row.count == 40)
    }

    @Test("The bar fills twenty cells in proportion to the fraction")
    func barCells() {
        #expect(ProgressRenderer.bar(0) == String(repeating: "░", count: 20))
        #expect(ProgressRenderer.bar(0.5) == String(repeating: "█", count: 10) + String(repeating: "░", count: 10))
        #expect(ProgressRenderer.bar(1) == String(repeating: "█", count: 20))
    }

    @Test("A fraction outside zero to one is clamped rather than drawn wrong")
    func barClamps() {
        #expect(ProgressRenderer.bar(-3) == String(repeating: "░", count: 20))
        #expect(ProgressRenderer.bar(4) == String(repeating: "█", count: 20))
    }

    @Test("A known fraction adds the bar and a right-aligned percentage")
    func lineWithBar() {
        let line = ProgressRenderer.line(
            spinner: "⠋",
            label: "voz: downloading 196 MB of 467 MB",
            fraction: 0.42,
            elapsed: 74,
            width: 120
        )
        #expect(line == "⠋ voz: downloading 196 MB of 467 MB 1:14 " + ProgressRenderer.bar(0.42) + "  42%")
    }

    @Test("Elapsed time reads as minutes and seconds, and minutes do not wrap into hours")
    func elapsedFormatting() {
        #expect(ProgressRenderer.elapsedText(0) == "0:00")
        #expect(ProgressRenderer.elapsedText(9) == "0:09")
        #expect(ProgressRenderer.elapsedText(59.9) == "0:59")
        #expect(ProgressRenderer.elapsedText(60) == "1:00")
        #expect(ProgressRenderer.elapsedText(74) == "1:14")
        #expect(ProgressRenderer.elapsedText(3_600) == "60:00")
        #expect(ProgressRenderer.elapsedText(-5) == "0:00")
    }

    // MARK: - Console handles

    @Test("A console with a renderer hands out live handles")
    func consoleLiveHandle() async {
        let sink = RecordingOutput()
        let renderer = ProgressRenderer(output: sink, width: 60)
        let console = Console(verbosity: .normal, renderer: renderer)
        let task = console.task("a.wav transcribing")
        #expect(task.isLive)
        await task.finish(line: "[1/1] a.wav -> a.txt (voz, 1.2 s)")
        #expect(sink.text.contains("[1/1] a.wav -> a.txt (voz, 1.2 s)\n"))
    }

    @Test("--quiet suppresses the live area even on a terminal")
    func quietHasNoLiveArea() async {
        let task = Console(verbosity: .quiet).task("a.wav transcribing")
        #expect(!task.isLive)
    }

    @Test("Standard error that is not a terminal gets a handle that draws nothing")
    func pipedConsoleHandle() {
        // The test runner's standard error is a pipe, which is the case the
        // piped byte-for-byte guarantee is about.
        let console = Console(verbosity: .normal)
        #expect(!console.isStandardErrorTTY)
        #expect(!console.task("a.wav transcribing").isLive)
    }
}

/// Checks what a piped run writes, by pointing standard error at a file.
///
/// The redirect is process wide, so the suite runs on its own and asserts on
/// what is present and what is absent rather than on the whole file.
@Suite("Progress output when piped", .serialized)
struct PipedProgressOutputTests {
    /// Runs `body` with standard error pointed at a temporary file and returns what was written.
    private func capturingStandardError(_ body: () async -> Void) async throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("speechkit-progress-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }

        let handle = try FileHandle(forWritingTo: url)
        let saved = dup(FileHandle.standardError.fileDescriptor)
        dup2(handle.fileDescriptor, FileHandle.standardError.fileDescriptor)
        await body()
        fsync(FileHandle.standardError.fileDescriptor)
        dup2(saved, FileHandle.standardError.fileDescriptor)
        close(saved)
        try handle.close()

        return String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    @Test("A piped task writes its finish and fail lines and nothing else")
    func pipedTaskWritesLinesOnly() async throws {
        let text = try await capturingStandardError {
            let console = Console(verbosity: .verbose)
            let first = console.task("a.wav transcribing")
            await first.update(label: "a.wav writing")
            await first.update(fraction: 0.5)
            await first.finish(line: "[1/2] a.wav -> a.txt (voz, 1.2 s)")

            let second = console.task("b.wav transcribing")
            await second.fail(line: "b.wav: the provider refused the file.")

            let third = console.task("c.wav transcribing")
            await third.finish()
            await console.task("d.wav transcribing").fail()
        }

        #expect(text.contains("[1/2] a.wav -> a.txt (voz, 1.2 s)\n"))
        #expect(text.contains("speechkit: b.wav: the provider refused the file.\n"))
        // No spinner, no bar, no escape sequence, and nothing at all for the
        // tasks that closed without a line.
        #expect(!text.contains("\u{1B}"))
        #expect(!text.contains("⠋"))
        #expect(!text.contains("█"))
        #expect(!text.contains("transcribing"))
        #expect(!text.contains("c.wav"))
        #expect(!text.contains("d.wav"))
    }

    @Test("At normal verbosity a piped finish line is held back, exactly as progress always was")
    func pipedNormalVerbosityIsSilent() async throws {
        let text = try await capturingStandardError {
            let console = Console(verbosity: .normal)
            await console.task("a.wav transcribing").finish(line: "[1/1] a.wav -> a.txt (voz, 1.2 s)")
        }
        #expect(!text.contains("a.wav"))
    }

    @Test("--quiet writes nothing at all, not even a failure line")
    func quietWritesNothing() async throws {
        let text = try await capturingStandardError {
            let console = Console(verbosity: .quiet)
            let task = console.task("a.wav transcribing")
            await task.update(fraction: 1)
            await task.finish(line: "[1/1] a.wav -> a.txt (voz, 1.2 s)")
        }
        #expect(!text.contains("a.wav"))
    }
}
