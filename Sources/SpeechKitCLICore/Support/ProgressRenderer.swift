import Darwin
import Dispatch
import Foundation

/// Where a ``ProgressRenderer`` writes its frames.
///
/// The real renderer writes to standard error. Tests pass a recorder and
/// assert the exact bytes, which is the only way to check escape sequences
/// without a terminal.
public protocol ProgressOutput: Sendable {
    /// Writes text with no trailing newline and no buffering of its own.
    func write(_ text: String)
}

/// The standard error sink the shared renderer uses.
struct StandardErrorProgressOutput: ProgressOutput {
    func write(_ text: String) {
        Console.writeStandardError(text)
    }
}

/// Tracks which renderer, if any, currently owns the bottom of the screen.
///
/// ``Console`` writes warnings and notes straight to standard error from
/// synchronous code, and the cursor is parked at the top left of the live area
/// while one is drawn. Knowing that without hopping onto the actor is what lets
/// a warning clear the live rows, print itself where they were, and leave the
/// cursor at the new origin for the next frame to redraw into.
enum ProgressLiveArea {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var owner: ProgressRenderer?

    /// The renderer drawing right now, or `nil` when the screen is plain.
    static var current: ProgressRenderer? {
        lock.withLock { owner }
    }

    /// Records that a renderer has taken, or given up, the live area.
    static func set(_ renderer: ProgressRenderer?) {
        lock.withLock { owner = renderer }
    }
}

/// Hands out the identifiers that tie a ``ProgressTask`` to a renderer row.
///
/// Identifiers are allocated outside the actor so `Console.task(_:)` can stay
/// synchronous: the handle exists the moment it is asked for, and the row
/// appears in the live area a hop later.
private final class ProgressTaskCounter: @unchecked Sendable {
    static let shared = ProgressTaskCounter()
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}

/// A handle on one line of the live progress area.
///
/// The same type covers both worlds. On a terminal it posts state to the
/// renderer; through a pipe, or under `--quiet`, it holds a verbosity and
/// prints exactly what ``Console/progress(_:)`` and ``Console/error(_:)``
/// printed before there was a live area, so piped output is unchanged.
///
/// Every method is asynchronous because the renderer is an actor. Calls made
/// from one task arrive in order, which is what keeps a finished line above
/// the row that replaced it.
public final class ProgressTask: @unchecked Sendable {
    private enum Backing {
        case live(id: Int, renderer: ProgressRenderer)
        case plain(Console.Verbosity)
    }

    private let backing: Backing
    private let started = Date()
    private let lock = NSLock()
    private var label: String
    private var fraction: Double?

    /// Creates a handle backed by the live area.
    init(label: String, renderer: ProgressRenderer) {
        self.label = label
        self.backing = .live(id: ProgressTaskCounter.shared.next(), renderer: renderer)
    }

    /// Creates a handle that prints finish and fail lines and nothing else.
    init(label: String, verbosity: Console.Verbosity) {
        self.label = label
        self.backing = .plain(verbosity)
    }

    /// Replaces the text shown for this task.
    ///
    /// This is how a file moves from `transcribing` to `writing`, and how the
    /// VOZ download reports the megabytes alongside its bar.
    public func update(label: String) async {
        lock.withLock { self.label = label }
        await push()
    }

    /// Whether this handle draws a row, or only prints its closing line.
    ///
    /// Callers that have plain output of their own to fall back on, such as
    /// the VOZ preparation lines, ask before choosing which to write.
    public var isLive: Bool {
        if case .live = backing { return true }
        return false
    }

    /// Sets the completed fraction, which draws a bar and a percentage.
    ///
    /// Values outside `0...1` are clamped by the renderer. `nil` takes the bar
    /// away again, for a phase whose length is not known.
    public func update(fraction: Double?) async {
        lock.withLock { self.fraction = fraction }
        await push()
    }

    /// Removes the task from the live area and prints a line above it.
    ///
    /// - Parameter line: The line, printed exactly as ``Console/progress(_:)``
    ///   would have printed it.
    public func finish(line: String) async {
        await complete(line: line, isFailure: false)
    }

    /// Removes the task from the live area and prints nothing.
    ///
    /// For work whose outcome is reported later, such as a `bench` row or a
    /// `keys check` table, where a per-task line would be new output that the
    /// piped form never had.
    public func finish() async {
        await complete(line: nil, isFailure: false)
    }

    /// Removes the task from the live area and prints a failure above it.
    ///
    /// - Parameter line: The message, printed exactly as ``Console/error(_:)``
    ///   would have printed it, `speechkit:` prefix included.
    public func fail(line: String) async {
        await complete(line: line, isFailure: true)
    }

    /// Removes the task from the live area and prints nothing.
    public func fail() async {
        await complete(line: nil, isFailure: true)
    }

    /// Posts the current state to the renderer, registering the row on first call.
    func push() async {
        guard case .live(let id, let renderer) = backing else { return }
        let (label, fraction) = lock.withLock { (self.label, self.fraction) }
        await renderer.set(id: id, label: label, fraction: fraction, started: started)
    }

    private func complete(line: String?, isFailure: Bool) async {
        switch backing {
        case .live(let id, let renderer):
            await renderer.complete(id: id, line: line, isFailure: isFailure)
        case .plain(let verbosity):
            guard let line else { return }
            let console = Console(verbosity: verbosity)
            if isFailure {
                console.error(line)
            } else {
                console.progress(line)
            }
        }
    }
}

/// Owns the bottom lines of the terminal, and is the only thing that writes
/// escape sequences.
///
/// A batch of concurrent uploads and the VOZ state stream would otherwise
/// fight over the cursor, so every caller posts state here through a
/// ``ProgressTask`` and the renderer decides what the screen looks like.
///
/// Frames are drawn at most twelve times a second, and only when something
/// changed or a quarter second has passed, which is enough for the elapsed
/// timers and cheap enough to be invisible.
public actor ProgressRenderer {
    /// One row of the live area.
    struct Entry {
        var id: Int
        var label: String
        var fraction: Double?
        var started: Date
    }

    /// The spinner frames, one per drawn frame.
    static let spinnerFrames: [String] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    /// How many cells a bar is drawn in.
    static let barCells = 20

    /// The shortest gap between two frames, in seconds.
    static let frameInterval: TimeInterval = 1.0 / 12.0

    /// How long an unchanged live area goes before it is redrawn anyway.
    ///
    /// The elapsed timers would otherwise stall on a task that reports nothing
    /// for minutes, which is exactly when a user is watching them.
    static let idleRedrawInterval: TimeInterval = 0.25

    /// The width assumed when `ioctl` cannot answer.
    static let fallbackWidth = 80

    /// The one renderer the process draws through.
    ///
    /// A `Console` is a value that is copied into every command, runner, and
    /// batch task, so the live area cannot live inside it. It lives here, is
    /// created the first time a terminal run asks for a task, and installs the
    /// signal handlers that keep the cursor from being left hidden.
    public static let shared: ProgressRenderer = {
        let renderer = ProgressRenderer(
            output: StandardErrorProgressOutput(),
            ownsStandardError: true
        )
        renderer.installSignalHandlers()
        return renderer
    }()

    private let output: any ProgressOutput
    private let overrideWidth: Int?
    private let ownsStandardError: Bool
    private var entries: [Entry] = []
    private var retired: Set<Int> = []
    private var spinnerIndex = 0
    private var lastDraw = Date.distantPast
    private var isDirty = false
    private var cursorHidden = false
    private var cachedWidth: Int?
    private var ticker: Task<Void, Never>?
    private nonisolated(unsafe) var signalSources: [DispatchSourceSignal] = []

    /// Creates a renderer.
    ///
    /// - Parameters:
    ///   - output: Where frames are written.
    ///   - width: A fixed column count, for tests. The real renderer reads the
    ///     terminal and re-reads it on `SIGWINCH`.
    public init(output: any ProgressOutput, width: Int? = nil) {
        self.output = output
        self.overrideWidth = width
        self.ownsStandardError = false
    }

    /// Creates the renderer that draws on the real terminal.
    ///
    /// Only this one claims ``ProgressLiveArea``, because only this one has
    /// rows on the screen that a warning printed to standard error would land
    /// on top of.
    init(output: any ProgressOutput, width: Int? = nil, ownsStandardError: Bool) {
        self.output = output
        self.overrideWidth = width
        self.ownsStandardError = ownsStandardError
    }

    // MARK: - Task state

    /// Adds a row, or updates the one this task already owns.
    func set(id: Int, label: String, fraction: Double?, started: Date) {
        // A frame that arrives after the task finished must not resurrect it.
        // The registration hop and the first update race, so this is not
        // theoretical.
        guard !retired.contains(id) else { return }
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].label = label
            entries[index].fraction = fraction
        } else {
            entries.append(Entry(id: id, label: label, fraction: fraction, started: started))
        }
        isDirty = true
        startTicker()
        drawIfNeeded()
    }

    /// Removes a row and prints its closing line above the live area.
    ///
    /// The live area is cleared, the line is written where the rows were, and
    /// the remaining rows are drawn again underneath it. Scrollback therefore
    /// holds the same lines a piped run would have written, in the same order,
    /// with no escape sequences left between them.
    func complete(id: Int, line: String?, isFailure: Bool) {
        retired.insert(id)
        entries.removeAll { $0.id == id }

        var frame = ""
        if cursorHidden {
            frame += Self.clearBelow
        }
        if let line {
            frame += (isFailure ? "speechkit: " + line : line) + "\n"
        }
        output.write(frame)
        spinnerIndex += 1
        draw()
    }

    // MARK: - Drawing

    private func drawIfNeeded() {
        let now = Date()
        let sinceLastDraw = now.timeIntervalSince(lastDraw)
        guard sinceLastDraw >= Self.frameInterval else { return }
        guard isDirty || sinceLastDraw >= Self.idleRedrawInterval else { return }
        draw()
    }

    private func draw() {
        lastDraw = Date()
        isDirty = false

        guard !entries.isEmpty else {
            var frame = cursorHidden ? Self.clearBelow : ""
            if cursorHidden {
                frame += Self.showCursor
                cursorHidden = false
                if ownsStandardError { ProgressLiveArea.set(nil) }
            }
            if !frame.isEmpty { output.write(frame) }
            stopTicker()
            return
        }

        let now = Date()
        let spinner = Self.spinnerFrames[spinnerIndex % Self.spinnerFrames.count]
        let columns = width()
        let lines = entries.map { entry in
            Self.line(
                spinner: spinner,
                label: entry.label,
                fraction: entry.fraction,
                elapsed: now.timeIntervalSince(entry.started),
                width: columns
            )
        }
        let hidesCursor = !cursorHidden
        cursorHidden = true
        if ownsStandardError { ProgressLiveArea.set(self) }
        output.write(Self.frame(lines: lines, hidesCursor: hidesCursor))
    }

    /// Draws the current state at once, ignoring the frame budget.
    ///
    /// Only tests call this. Sleeping for the ticker instead would make every
    /// frame assertion depend on how many frames the ticker managed to draw
    /// first, which is the opposite of a golden test.
    func drawImmediately() {
        draw()
    }

    /// Redraws after something else wrote over the live rows.
    ///
    /// ``Console`` clears the area itself before printing a warning, so the
    /// rows have to be put back. The next tick would do it within a frame
    /// anyway; this just makes it immediate when the frame budget allows.
    func redrawSoon() {
        isDirty = true
        drawIfNeeded()
    }

    private func tick() {
        guard !entries.isEmpty else {
            stopTicker()
            return
        }
        spinnerIndex += 1
        isDirty = true
        drawIfNeeded()
    }

    private func startTicker() {
        guard ticker == nil, !entries.isEmpty else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Int(Self.frameInterval * 1000)))
                guard let self else { return }
                await self.tick()
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    // MARK: - Frame composition

    /// Hides the cursor, so a spinner does not drag a block around the screen.
    static let hideCursor = "\u{1B}[?25l"

    /// Restores the cursor. Every exit path writes this.
    static let showCursor = "\u{1B}[?25h"

    /// Clears from the cursor to the end of the screen.
    ///
    /// The cursor always rests at the first column of the first live row, so
    /// this erases the whole live area and nothing above it.
    static let clearBelow = "\u{1B}[0J"

    /// Returns the bytes for one frame.
    ///
    /// The cursor is left at the start of the first line, which is what makes
    /// the next frame a single clear-and-redraw.
    ///
    /// - Parameters:
    ///   - lines: The rows, already truncated to the terminal width.
    ///   - hidesCursor: Whether this frame is the one that hides the cursor.
    static func frame(lines: [String], hidesCursor: Bool) -> String {
        var frame = hidesCursor ? hideCursor : ""
        frame += clearBelow
        frame += lines.joined(separator: "\n")
        if lines.count > 1 {
            frame += "\u{1B}[\(lines.count - 1)A"
        }
        frame += "\r"
        return frame
    }

    /// Returns one live row.
    ///
    /// - Parameters:
    ///   - spinner: The current spinner frame.
    ///   - label: What the task is doing.
    ///   - elapsed: Seconds since the task started.
    ///   - fraction: The completed fraction, when one is known.
    ///   - width: The terminal width the row is truncated to.
    static func line(
        spinner: String,
        label: String,
        fraction: Double?,
        elapsed: TimeInterval,
        width: Int
    ) -> String {
        var text = spinner + " " + label + " " + elapsedText(elapsed)
        if let fraction {
            text += " " + bar(fraction) + " " + percentText(fraction)
        }
        return truncate(text, to: width)
    }

    /// Returns elapsed seconds as `m:ss`.
    ///
    /// Minutes are not wrapped into hours: a forty-minute first VOZ load reads
    /// better as `40:12` than as `0:40:12`.
    static func elapsedText(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Returns a bar of ``barCells`` cells for a fraction.
    static func bar(_ fraction: Double) -> String {
        let clamped = min(max(fraction, 0), 1)
        let filled = Int((clamped * Double(barCells)).rounded())
        return String(repeating: "█", count: filled)
            + String(repeating: "░", count: barCells - filled)
    }

    /// Returns a fraction as a right-aligned percentage.
    ///
    /// The width is fixed so the row does not jitter as the number grows.
    static func percentText(_ fraction: Double) -> String {
        let clamped = min(max(fraction, 0), 1)
        return String(format: "%3d%%", Int((clamped * 100).rounded()))
    }

    /// Returns text cut to a column count, with an ellipsis where it was cut.
    ///
    /// A row that wraps corrupts the redraw, because the cursor arithmetic
    /// counts rows the terminal has split in two.
    static func truncate(_ text: String, to width: Int) -> String {
        guard width > 0 else { return "" }
        guard text.count > width else { return text }
        return String(text.prefix(width - 1)) + "…"
    }

    // MARK: - Terminal width

    private func width() -> Int {
        if let overrideWidth { return overrideWidth }
        if let cachedWidth { return cachedWidth }
        let measured = Self.terminalWidth() ?? Self.fallbackWidth
        cachedWidth = measured
        return measured
    }

    /// Returns the column count of standard error, or `nil` when it has none.
    static func terminalWidth() -> Int? {
        var size = winsize()
        guard ioctl(FileHandle.standardError.fileDescriptor, TIOCGWINSZ, &size) == 0 else { return nil }
        guard size.ws_col > 0 else { return nil }
        return Int(size.ws_col)
    }

    private func invalidateWidth() {
        cachedWidth = nil
        isDirty = true
        drawIfNeeded()
    }

    // MARK: - Signals

    /// Watches for resizes and interrupts.
    ///
    /// Only ``shared`` installs these. A renderer built for a test must not
    /// take over the process's signals, and must never call `exit`.
    nonisolated func installSignalHandlers() {
        let queue = DispatchQueue(label: "speechkit.progress.signals")

        signal(SIGWINCH, SIG_IGN)
        let resize = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: queue)
        resize.setEventHandler { Task { await self.invalidateWidth() } }
        resize.resume()

        // Without this the default handler kills the process before the
        // dispatch source runs, and the terminal keeps a hidden cursor.
        signal(SIGINT, SIG_IGN)
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: queue)
        interrupt.setEventHandler { Task { await self.interrupt() } }
        interrupt.resume()

        signalSources = [resize, interrupt]
    }

    /// Clears the live area, restores the cursor, and exits 130.
    ///
    /// Interactive mode registers its raw-mode restoration with
    /// ``TerminalRestoration`` rather than installing a second `SIGINT`
    /// handler, so one interrupt path undoes both the live area and the
    /// terminal settings, and the exit code stays 130 either way.
    func interrupt() {
        TerminalRestoration.run()
        var frame = ""
        if cursorHidden {
            frame += Self.clearBelow + Self.showCursor
            cursorHidden = false
            if ownsStandardError { ProgressLiveArea.set(nil) }
        }
        frame += "\n"
        output.write(frame)
        exit(130)
    }
}
