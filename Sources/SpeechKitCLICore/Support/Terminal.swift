import Darwin
import Foundation

/// One keystroke, decoded from the bytes a terminal sends in raw mode.
///
/// Only the keys the prompts act on are modelled. Anything else printable
/// arrives as ``character(_:)`` and anything else at all is dropped by the
/// reader, so an unrecognised escape sequence can never be mistaken for a
/// bare escape and walk the user back a step.
public enum Key: Sendable, Equatable {
    /// The up arrow, or `k` where a prompt maps it.
    case up
    /// The down arrow, or `j` where a prompt maps it.
    case down
    /// The left arrow.
    case left
    /// The right arrow.
    case right
    /// Return or enter.
    case enter
    /// A bare escape, already distinguished from an escape sequence.
    case escape
    /// Tab.
    case tab
    /// The space bar.
    case space
    /// Delete or backspace.
    case backspace
    /// `Ctrl-C`.
    case controlC
    /// `Ctrl-D`.
    case controlD
    /// A printable character.
    case character(Character)
}

/// Something a prompt can read keys from.
///
/// The real implementation is ``Terminal``. Tests drive the prompt state
/// machines directly, and the few that exercise the reader hand it a script
/// of keys through ``ScriptedKeyReader``.
public protocol KeyReader: AnyObject {
    /// Returns the next keystroke, or `nil` when the input ended.
    func readKey() -> Key?
}

/// A key reader that replays a fixed list, for tests.
final class ScriptedKeyReader: KeyReader {
    private var keys: [Key]

    init(_ keys: [Key]) {
        self.keys = keys
    }

    func readKey() -> Key? {
        keys.isEmpty ? nil : keys.removeFirst()
    }
}

/// Remembers how to put the terminal back, for the paths that cannot use `defer`.
///
/// A `SIGINT` arriving while the tool is in raw mode is handled by
/// ``ProgressRenderer/shared``, which clears its live area and exits 130. It
/// has to undo the raw mode first, or the shell that receives control back
/// echoes nothing. Registering the restoration here rather than installing a
/// second signal handler keeps one interrupt path in the process, so the exit
/// code stays 130 and the two cleanups cannot race.
enum TerminalRestoration {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (@Sendable () -> Void)?

    /// Records what to run if the process is interrupted, or clears it.
    static func set(_ handler: (@Sendable () -> Void)?) {
        lock.withLock { self.handler = handler }
    }

    /// Runs the registered restoration once, if there is one.
    static func run() {
        let handler = lock.withLock { self.handler }
        handler?()
    }
}

/// Puts the terminal into raw mode, decodes keystrokes, and always puts it back.
///
/// Prompts are drawn on standard error, so standard output stays a clean pipe
/// even while a form is on screen. Output post-processing is deliberately left
/// on: `cfmakeraw` would clear `OPOST` too, and then every `\n` the renderer
/// writes would step down a line without returning to column one.
final class Terminal: KeyReader {
    /// How long a lone escape byte is given to turn out to be a sequence.
    ///
    /// Arrow keys arrive as three bytes in one burst, so anything that has not
    /// followed within this window came from the escape key itself.
    static let escapeTimeoutMilliseconds: Int32 = 40

    /// The width assumed when the terminal cannot be measured.
    static let fallbackWidth = 80

    private let input: Int32
    private var saved: termios?

    /// Creates a terminal over a file descriptor.
    ///
    /// - Parameter input: The descriptor keys are read from, standard input by
    ///   default.
    init(input: Int32 = FileHandle.standardInput.fileDescriptor) {
        self.input = input
    }

    /// Whether standard input and standard error are both terminals.
    ///
    /// Both halves matter: the prompts read from one and draw on the other, so
    /// a redirected either way is not an interactive session.
    static func isInteractive(
        input: Int32 = FileHandle.standardInput.fileDescriptor,
        error: Int32 = FileHandle.standardError.fileDescriptor
    ) -> Bool {
        isatty(input) == 1 && isatty(error) == 1
    }

    // MARK: - Raw mode

    /// Turns off line buffering, echo, and signal generation.
    ///
    /// With `ISIG` off, `Ctrl-C` arrives as the byte `0x03` rather than a
    /// signal, which is what lets a prompt exit 130 through the same path a
    /// cancelled prompt takes.
    ///
    /// - Throws: ``CLIError/usage(_:)`` when the descriptor is not a terminal.
    func enterRawMode() throws {
        var current = termios()
        guard tcgetattr(input, &current) == 0 else {
            throw CLIError.usage("Standard input is not a terminal.")
        }
        saved = current

        var raw = current
        raw.c_iflag &= ~tcflag_t(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | IEXTEN | ISIG)
        raw.c_cflag |= tcflag_t(CS8)
        // Output post-processing stays on, so a newline still returns the
        // cursor to column one and multi-line frames line up.
        withUnsafeMutableBytes(of: &raw.c_cc) { control in
            control[Int(VMIN)] = 1
            control[Int(VTIME)] = 0
        }
        guard tcsetattr(input, TCSAFLUSH, &raw) == 0 else {
            throw CLIError.usage("The terminal refused raw mode.")
        }

        // The interrupt handler lives in the progress renderer, which is
        // touched here so its signal sources exist even if no live row is ever
        // drawn.
        let descriptor = input
        let restoreTo = current
        TerminalRestoration.set {
            var attributes = restoreTo
            _ = tcsetattr(descriptor, TCSAFLUSH, &attributes)
            Console.writeStandardError(ProgressRenderer.showCursor)
        }
        _ = ProgressRenderer.shared
    }

    /// Puts the terminal back the way it was, and shows the cursor.
    ///
    /// Safe to call more than once: the second call has nothing saved to
    /// restore and does nothing.
    func restore() {
        TerminalRestoration.set(nil)
        guard var saved else { return }
        self.saved = nil
        _ = tcsetattr(input, TCSAFLUSH, &saved)
        showCursor()
    }

    // MARK: - Reading

    /// Returns the next keystroke, or `nil` at end of input.
    func readKey() -> Key? {
        guard let first = readByte() else { return nil }
        switch first {
        case 0x03: return .controlC
        case 0x04: return .controlD
        case 0x09: return .tab
        case 0x0A, 0x0D: return .enter
        case 0x7F, 0x08: return .backspace
        case 0x20: return .space
        case 0x1B: return readEscape()
        default:
            guard first >= 0x20 else { return readKey() }
            return character(startingWith: first)
        }
    }

    /// Decodes what follows an escape byte.
    ///
    /// Nothing within ``escapeTimeoutMilliseconds`` means the escape key was
    /// pressed on its own. A `[` or `O` introduces a sequence, whose final
    /// byte is consumed whether or not this code understands it.
    private func readEscape() -> Key? {
        guard let next = readByte(waitingMilliseconds: Self.escapeTimeoutMilliseconds) else {
            return .escape
        }
        guard next == 0x5B || next == 0x4F else { return .escape }

        var final: UInt8?
        // Parameter and intermediate bytes run 0x30...0x3F and 0x20...0x2F; the
        // final byte is 0x40...0x7E. Reading to it keeps a modified arrow key
        // from leaving digits in the buffer for the next prompt to type.
        while let byte = readByte(waitingMilliseconds: Self.escapeTimeoutMilliseconds) {
            if byte >= 0x40 {
                final = byte
                break
            }
        }
        switch final {
        case 0x41: return .up
        case 0x42: return .down
        case 0x43: return .right
        case 0x44: return .left
        default: return readKey()
        }
    }

    /// Reads the continuation bytes of a UTF-8 scalar and returns the character.
    private func character(startingWith first: UInt8) -> Key? {
        var bytes: [UInt8] = [first]
        let extra: Int
        switch first {
        case 0xC0...0xDF: extra = 1
        case 0xE0...0xEF: extra = 2
        case 0xF0...0xF7: extra = 3
        default: extra = 0
        }
        for _ in 0..<extra {
            guard let byte = readByte(waitingMilliseconds: Self.escapeTimeoutMilliseconds) else { break }
            bytes.append(byte)
        }
        guard let character = String(decoding: bytes, as: UTF8.self).first else { return readKey() }
        return .character(character)
    }

    /// Reads one byte, blocking, or `nil` when the input ended.
    private func readByte() -> UInt8? {
        var byte: UInt8 = 0
        while true {
            let count = read(input, &byte, 1)
            if count == 1 { return byte }
            if count == -1, errno == EINTR { continue }
            return nil
        }
    }

    /// Reads one byte if one arrives within a deadline.
    private func readByte(waitingMilliseconds milliseconds: Int32) -> UInt8? {
        var descriptor = pollfd(fd: input, events: Int16(POLLIN), revents: 0)
        let ready = poll(&descriptor, 1, milliseconds)
        guard ready > 0 else { return nil }
        return readByte()
    }

    // MARK: - Drawing

    /// Writes text to standard error, where every prompt draws.
    func write(_ text: String) {
        Console.writeStandardError(text)
    }

    /// Hides the cursor, so it does not sit in the middle of a redrawn form.
    func hideCursor() {
        write(ProgressRenderer.hideCursor)
    }

    /// Shows the cursor again. Every exit path writes this.
    func showCursor() {
        write(ProgressRenderer.showCursor)
    }

    /// The column count of the terminal, or ``fallbackWidth`` when it has none.
    static func width() -> Int {
        ProgressRenderer.terminalWidth() ?? fallbackWidth
    }
}
