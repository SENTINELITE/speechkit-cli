import Foundation

/// What a prompt decided after one keystroke.
///
/// Prompts never read or draw anything themselves, so every flow in
/// ``Interactive`` is a loop over these four answers and every prompt is
/// testable by handing it a list of keys.
public enum PromptOutcome<Value: Equatable & Sendable>: Equatable, Sendable {
    /// The prompt is still waiting; redraw and read another key.
    case `continue`
    /// The prompt is answered.
    case submit(Value)
    /// Escape: the flow steps back to the previous prompt.
    case back
    /// `Ctrl-C` or `Ctrl-D`: the session ends.
    case cancel
}

/// A prompt: a state machine over keys, plus a way to draw itself.
///
/// Drawing is a pure function of the state to a list of lines, so a test can
/// assert what the user would see without a terminal, and the runner can
/// redraw by clearing and writing the lines again.
public protocol Prompt {
    /// What the prompt returns when it is answered.
    associatedtype Value: Equatable & Sendable

    /// The question, used in the prompt line and in the summary it leaves behind.
    var title: String { get }

    /// Advances the state by one keystroke.
    mutating func apply(_ key: Key) -> PromptOutcome<Value>

    /// Returns the lines to draw, already truncated to `width`.
    func render(width: Int) -> [String]

    /// Returns the one line left in the scrollback once the prompt is answered.
    func summary(for value: Value) -> String
}

/// The characters and spacing every prompt shares.
public enum PromptStyle {
    /// The marker in front of an unanswered question.
    public static let question = "?"
    /// The marker in front of the highlighted row.
    public static let pointer = "›"
    /// A selected multi-select row.
    public static let checked = "◉"
    /// An unselected multi-select row.
    public static let unchecked = "◯"

    /// Returns the line a prompt leaves behind, such as `? Provider  voz`.
    public static func summary(title: String, value: String) -> String {
        "\(question) \(title)  \(value)"
    }

    /// Returns the prompt's own first line, with an optional hint after it.
    static func header(_ title: String, hint: String?) -> String {
        guard let hint, !hint.isEmpty else { return "\(question) \(title)" }
        return "\(question) \(title)  \(hint)"
    }

    /// Cuts a line to the terminal width, so a wrapped row cannot corrupt a redraw.
    static func fit(_ line: String, width: Int) -> String {
        ProgressRenderer.truncate(line, to: width)
    }
}

// MARK: - Select

/// One row of a select or multi-select prompt.
public struct SelectItem: Equatable, Sendable {
    /// The value submitted when the row is chosen.
    public let id: String
    /// The text shown for the row.
    public let title: String
    /// Dimmer text after the title, such as a provider's credential status.
    public let detail: String?

    /// Creates a row.
    public init(id: String, title: String, detail: String? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
    }

    /// Creates a row whose identifier is its title.
    public init(_ title: String, detail: String? = nil) {
        self.init(id: title, title: title, detail: detail)
    }

    /// Whether the row matches a type-to-filter string.
    func matches(_ filter: String) -> Bool {
        guard !filter.isEmpty else { return true }
        let needle = filter.lowercased()
        return title.lowercased().contains(needle) || id.lowercased().contains(needle)
    }
}

/// Pick one of a list with the arrow keys, `j` and `k`, or by typing.
///
/// Typing filters rather than jumping, because provider and format names share
/// prefixes and a filter shows what else was possible.
public struct SelectPrompt: Prompt {
    /// The question.
    public let title: String
    /// Every row, before filtering.
    public let items: [SelectItem]
    /// The type-to-filter text.
    public private(set) var filter: String = ""
    /// The highlighted row, as an index into ``visibleItems``.
    public private(set) var index: Int = 0

    /// Creates a select prompt.
    ///
    /// - Parameters:
    ///   - title: The question.
    ///   - items: The rows, in the order they are shown.
    ///   - selectedID: The row highlighted first, such as the provider the last
    ///     run used.
    public init(title: String, items: [SelectItem], selectedID: String? = nil) {
        self.title = title
        self.items = items
        if let selectedID, let start = items.firstIndex(where: { $0.id == selectedID }) {
            self.index = start
        }
    }

    /// The rows the filter allows through.
    public var visibleItems: [SelectItem] {
        items.filter { $0.matches(filter) }
    }

    /// Advances the state by one keystroke.
    public mutating func apply(_ key: Key) -> PromptOutcome<String> {
        let visible = visibleItems
        switch key {
        case .controlC, .controlD:
            return .cancel
        case .escape:
            return .back
        case .up:
            move(by: -1, count: visible.count)
        case .down:
            move(by: 1, count: visible.count)
        case .enter:
            guard index < visible.count else { return .continue }
            return .submit(visible[index].id)
        case .backspace:
            guard !filter.isEmpty else { return .continue }
            filter.removeLast()
            index = 0
        case .space:
            guard !filter.isEmpty else { return .continue }
            filter.append(" ")
            index = 0
        case .character(let character):
            // `j` and `k` steer only while nothing has been typed, so they can
            // still be typed into a filter.
            if filter.isEmpty, character == "j" {
                move(by: 1, count: visible.count)
            } else if filter.isEmpty, character == "k" {
                move(by: -1, count: visible.count)
            } else {
                filter.append(character)
                index = 0
            }
        case .left, .right, .tab:
            return .continue
        }
        return .continue
    }

    private mutating func move(by offset: Int, count: Int) {
        guard count > 0 else {
            index = 0
            return
        }
        index = ((index + offset) % count + count) % count
    }

    /// Returns the lines to draw.
    public func render(width: Int) -> [String] {
        var lines = [PromptStyle.fit(PromptStyle.header(title, hint: filter.isEmpty ? nil : filter), width: width)]
        let visible = visibleItems
        if visible.isEmpty {
            lines.append(PromptStyle.fit("  no matches", width: width))
        }
        for (position, item) in visible.enumerated() {
            lines.append(PromptStyle.fit(Self.row(item, selected: position == index), width: width))
        }
        return lines
    }

    /// Returns one drawn row.
    static func row(_ item: SelectItem, selected: Bool) -> String {
        var line = (selected ? PromptStyle.pointer : " ") + " " + item.title
        if let detail = item.detail {
            line += "  (\(detail))"
        }
        return line
    }

    /// Returns the line left behind once a row is chosen.
    public func summary(for value: String) -> String {
        let title = items.first { $0.id == value }?.title ?? value
        return PromptStyle.summary(title: self.title, value: title)
    }
}

// MARK: - Multi select

/// Toggle any number of rows with the space bar, then confirm with enter.
public struct MultiSelectPrompt: Prompt {
    /// The question.
    public let title: String
    /// Every row, before filtering.
    public let items: [SelectItem]
    /// Whether enter is allowed to submit nothing.
    public let allowsEmpty: Bool
    /// The type-to-filter text.
    public private(set) var filter: String = ""
    /// The highlighted row, as an index into ``visibleItems``.
    public private(set) var index: Int = 0
    /// The chosen identifiers.
    public private(set) var selected: Set<String>

    /// Creates a multi-select prompt.
    ///
    /// - Parameters:
    ///   - title: The question.
    ///   - items: The rows, in the order they are shown.
    ///   - selectedIDs: The rows ticked first, such as the formats of the last run.
    ///   - allowsEmpty: Whether an empty answer may be submitted.
    public init(
        title: String,
        items: [SelectItem],
        selectedIDs: [String] = [],
        allowsEmpty: Bool = false
    ) {
        self.title = title
        self.items = items
        self.selected = Set(selectedIDs.filter { id in items.contains { $0.id == id } })
        self.allowsEmpty = allowsEmpty
    }

    /// The rows the filter allows through.
    public var visibleItems: [SelectItem] {
        items.filter { $0.matches(filter) }
    }

    /// The chosen identifiers, in the order the rows are listed.
    public var chosen: [String] {
        items.map(\.id).filter { selected.contains($0) }
    }

    /// Advances the state by one keystroke.
    public mutating func apply(_ key: Key) -> PromptOutcome<[String]> {
        let visible = visibleItems
        switch key {
        case .controlC, .controlD:
            return .cancel
        case .escape:
            return .back
        case .up:
            move(by: -1, count: visible.count)
        case .down:
            move(by: 1, count: visible.count)
        case .space:
            // Space toggles rather than typing, which is why a filter here is
            // built from the other printable keys only.
            guard index < visible.count else { return .continue }
            let id = visible[index].id
            if selected.contains(id) {
                selected.remove(id)
            } else {
                selected.insert(id)
            }
        case .enter:
            let answer = chosen
            guard allowsEmpty || !answer.isEmpty else { return .continue }
            return .submit(answer)
        case .backspace:
            guard !filter.isEmpty else { return .continue }
            filter.removeLast()
            index = 0
        case .character(let character):
            if filter.isEmpty, character == "j" {
                move(by: 1, count: visible.count)
            } else if filter.isEmpty, character == "k" {
                move(by: -1, count: visible.count)
            } else {
                filter.append(character)
                index = 0
            }
        case .left, .right, .tab:
            return .continue
        }
        return .continue
    }

    private mutating func move(by offset: Int, count: Int) {
        guard count > 0 else {
            index = 0
            return
        }
        index = ((index + offset) % count + count) % count
    }

    /// Returns the lines to draw.
    public func render(width: Int) -> [String] {
        let hint = filter.isEmpty ? "space toggles, enter confirms" : filter
        var lines = [PromptStyle.fit(PromptStyle.header(title, hint: hint), width: width)]
        let visible = visibleItems
        if visible.isEmpty {
            lines.append(PromptStyle.fit("  no matches", width: width))
        }
        for (position, item) in visible.enumerated() {
            let mark = selected.contains(item.id) ? PromptStyle.checked : PromptStyle.unchecked
            var line = (position == index ? PromptStyle.pointer : " ") + " " + mark + " " + item.title
            if let detail = item.detail {
                line += "  (\(detail))"
            }
            lines.append(PromptStyle.fit(line, width: width))
        }
        return lines
    }

    /// Returns the line left behind once the rows are confirmed.
    public func summary(for value: [String]) -> String {
        let titles = value.map { id in items.first { $0.id == id }?.title ?? id }
        return PromptStyle.summary(
            title: title,
            value: titles.isEmpty ? "none" : titles.joined(separator: ", ")
        )
    }
}

// MARK: - Text

/// Type a line, with a default and a movable cursor.
public struct TextPrompt: Prompt {
    /// The question.
    public let title: String
    /// What enter submits when nothing was typed.
    public let defaultValue: String?
    /// Whether the text is drawn as bullets, for an API key.
    public let isSecret: Bool
    /// What has been typed.
    public private(set) var text: String
    /// Where the next character goes, as an offset into ``text``.
    public private(set) var cursor: Int

    /// Creates a text prompt.
    ///
    /// - Parameters:
    ///   - title: The question.
    ///   - defaultValue: What enter submits on an empty line.
    ///   - text: The text the prompt opens with, already editable.
    ///   - isSecret: Whether to draw bullets instead of the characters.
    public init(
        title: String,
        defaultValue: String? = nil,
        text: String = "",
        isSecret: Bool = false
    ) {
        self.title = title
        self.defaultValue = defaultValue
        self.isSecret = isSecret
        self.text = text
        self.cursor = text.count
    }

    /// Advances the state by one keystroke.
    public mutating func apply(_ key: Key) -> PromptOutcome<String> {
        switch key {
        case .controlC, .controlD:
            return .cancel
        case .escape:
            return .back
        case .enter:
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                guard let defaultValue else { return .continue }
                return .submit(defaultValue)
            }
            return .submit(isSecret ? text : trimmed)
        case .backspace:
            guard cursor > 0 else { return .continue }
            text.remove(at: text.index(text.startIndex, offsetBy: cursor - 1))
            cursor -= 1
        case .left:
            cursor = max(0, cursor - 1)
        case .right:
            cursor = min(text.count, cursor + 1)
        case .space:
            insert(" ")
        case .character(let character):
            insert(character)
        case .up, .down, .tab:
            return .continue
        }
        return .continue
    }

    private mutating func insert(_ character: Character) {
        text.insert(character, at: text.index(text.startIndex, offsetBy: cursor))
        cursor += 1
    }

    /// The text as it is drawn, bulleted when the prompt is a secret.
    public var displayText: String {
        isSecret ? String(repeating: "•", count: text.count) : text
    }

    /// Returns the lines to draw.
    public func render(width: Int) -> [String] {
        var line = PromptStyle.header(title, hint: nil) + "  " + displayText
        if text.isEmpty, let defaultValue, !isSecret {
            line += "(\(defaultValue))"
        }
        return [PromptStyle.fit(line, width: width)]
    }

    /// Returns the line left behind once the text is submitted.
    public func summary(for value: String) -> String {
        PromptStyle.summary(
            title: title,
            value: isSecret ? String(repeating: "•", count: max(value.count, 1)) : value
        )
    }
}

// MARK: - Path

/// Lists the paths that could complete a partial one.
///
/// The real one reads the file system. Tests pass a closure over a temporary
/// directory, so completion is exercised without touching the user's home.
public typealias PathLister = @Sendable (String) -> [String]

/// Type a path, with tab completion against the file system.
public struct PathPrompt: Prompt {
    /// How many completions are listed under the prompt.
    public static let maxMatches = 8

    /// The question.
    public let title: String
    /// What has been typed.
    public private(set) var text: String
    /// The completions from the last tab, at most ``maxMatches`` of them.
    public private(set) var matches: [String] = []
    /// How many completions the last tab found, which can exceed what is shown.
    public private(set) var matchCount = 0

    private let lister: PathLister

    /// Creates a path prompt.
    ///
    /// - Parameters:
    ///   - title: The question.
    ///   - text: The path the prompt opens with.
    ///   - lister: What tab completes against.
    public init(
        title: String,
        text: String = "",
        lister: @escaping PathLister = PathPrompt.fileSystemLister
    ) {
        self.title = title
        self.text = text
        self.lister = lister
    }

    /// Advances the state by one keystroke.
    public mutating func apply(_ key: Key) -> PromptOutcome<String> {
        switch key {
        case .controlC, .controlD:
            return .cancel
        case .escape:
            return .back
        case .enter:
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return .continue }
            return .submit(trimmed)
        case .tab:
            complete()
        case .backspace:
            guard !text.isEmpty else { return .continue }
            text.removeLast()
            matches = []
            matchCount = 0
        case .space:
            insert(" ")
        case .character(let character):
            insert(character)
        case .up, .down, .left, .right:
            return .continue
        }
        return .continue
    }

    private mutating func insert(_ character: Character) {
        text.append(character)
        matches = []
        matchCount = 0
    }

    /// Completes as far as the candidates agree, and lists what is left.
    ///
    /// One candidate completes outright. Several extend the text to their
    /// common prefix, which is what makes repeated tabs walk down a tree, and
    /// the first few are listed so the next keystroke is an informed one.
    private mutating func complete() {
        let candidates = lister(text)
        matchCount = candidates.count
        guard !candidates.isEmpty else {
            matches = []
            return
        }
        if candidates.count == 1 {
            text = candidates[0]
            matches = []
            return
        }
        let shared = Self.commonPrefix(of: candidates)
        if shared.count > text.count {
            text = shared
        }
        matches = Array(candidates.prefix(Self.maxMatches))
    }

    /// Returns the longest prefix every candidate starts with.
    static func commonPrefix(of candidates: [String]) -> String {
        guard var shared = candidates.first else { return "" }
        for candidate in candidates.dropFirst() {
            shared = String(shared.commonPrefix(with: candidate))
        }
        return shared
    }

    /// Returns the lines to draw.
    public func render(width: Int) -> [String] {
        var lines = [
            PromptStyle.fit(PromptStyle.header(title, hint: "tab completes") + "  " + text, width: width)
        ]
        for match in matches {
            lines.append(PromptStyle.fit("    " + (match as NSString).lastPathComponent, width: width))
        }
        if matchCount > matches.count, !matches.isEmpty {
            lines.append(PromptStyle.fit("    … \(matchCount - matches.count) more", width: width))
        }
        return lines
    }

    /// Returns the line left behind once the path is submitted.
    public func summary(for value: String) -> String {
        PromptStyle.summary(title: title, value: value)
    }

    /// The completion source that reads the file system.
    ///
    /// A directory is completed with a trailing slash, so a second tab walks
    /// into it rather than stopping at its name.
    public static let fileSystemLister: PathLister = { partial in
        let expanded = (partial as NSString).expandingTildeInPath
        let directory = expanded.hasSuffix("/")
            ? expanded
            : (expanded as NSString).deletingLastPathComponent
        let prefix = expanded.hasSuffix("/") ? "" : (expanded as NSString).lastPathComponent
        let searched = directory.isEmpty ? "." : directory
        let manager = FileManager.default
        let entries = (try? manager.contentsOfDirectory(atPath: searched)) ?? []
        return entries
            .filter { $0.hasPrefix(prefix) && (prefix.hasPrefix(".") || !$0.hasPrefix(".")) }
            .sorted()
            .map { name in
                let joined = directory.isEmpty ? name : (directory as NSString).appendingPathComponent(name)
                var isDirectory: ObjCBool = false
                _ = manager.fileExists(atPath: joined, isDirectory: &isDirectory)
                return isDirectory.boolValue ? joined + "/" : joined
            }
    }
}

// MARK: - Confirm

/// A yes or no question, answered with `y`, `n`, or the arrow keys and enter.
public struct ConfirmPrompt: Prompt {
    /// The question.
    public let title: String
    /// The highlighted answer.
    public private(set) var value: Bool

    /// Creates a confirmation.
    ///
    /// - Parameters:
    ///   - title: The question.
    ///   - value: The answer highlighted first.
    public init(title: String, value: Bool = false) {
        self.title = title
        self.value = value
    }

    /// Advances the state by one keystroke.
    public mutating func apply(_ key: Key) -> PromptOutcome<Bool> {
        switch key {
        case .controlC, .controlD:
            return .cancel
        case .escape:
            return .back
        case .enter:
            return .submit(value)
        case .left, .right, .up, .down, .tab, .space:
            value.toggle()
        case .character(let character):
            switch character {
            case "y", "Y": return .submit(true)
            case "n", "N": return .submit(false)
            default: return .continue
            }
        case .backspace:
            return .continue
        }
        return .continue
    }

    /// Returns the lines to draw.
    public func render(width: Int) -> [String] {
        let yes = value ? "\(PromptStyle.pointer) Yes" : "  Yes"
        let no = value ? "  No" : "\(PromptStyle.pointer) No"
        return [PromptStyle.fit(PromptStyle.header(title, hint: nil) + " " + yes + " " + no, width: width)]
    }

    /// Returns the line left behind once the question is answered.
    public func summary(for value: Bool) -> String {
        PromptStyle.summary(title: title, value: value ? "Yes" : "No")
    }
}

// MARK: - Running

/// Draws prompts on a terminal and feeds them keys.
///
/// The runner owns the few lines a prompt occupies: it clears them on every
/// keystroke, redraws, and on an answer replaces the whole block with the
/// prompt's one-line summary. The scrollback that results reads like a filled
/// in form rather than a transcript of arrow keys. Nothing is ever written to
/// standard output, so a transcript piped out of a run started here is as
/// clean as one from a headless run.
final class PromptRunner {
    private let reader: KeyReader
    private let write: (String) -> Void
    private let width: () -> Int

    /// Creates a runner.
    ///
    /// - Parameters:
    ///   - reader: Where keys come from.
    ///   - width: The terminal width, re-read for every frame.
    ///   - write: Where frames go, standard error in a real session.
    init(
        reader: KeyReader,
        width: @escaping () -> Int = { Terminal.width() },
        write: @escaping (String) -> Void = { Console.writeStandardError($0) }
    ) {
        self.reader = reader
        self.width = width
        self.write = write
    }

    /// Draws a prompt until it is answered, cancelled, or stepped back from.
    ///
    /// - Parameter prompt: The prompt, taken by value: its state belongs to
    ///   this call and nothing outside it can see a half-typed answer.
    /// - Returns: The outcome. An input that ends without an answer reads as
    ///   ``PromptOutcome/cancel``, which is what a closed pipe means.
    func run<P: Prompt>(_ prompt: P) -> PromptOutcome<P.Value> {
        var prompt = prompt
        draw(prompt.render(width: width()))
        while let key = reader.readKey() {
            switch prompt.apply(key) {
            case .continue:
                draw(prompt.render(width: width()))
            case .submit(let value):
                clear()
                write(prompt.summary(for: value) + "\n")
                return .submit(value)
            case .back:
                clear()
                return .back
            case .cancel:
                clear()
                return .cancel
            }
        }
        clear()
        return .cancel
    }

    /// Writes one frame, leaving the cursor at the top left of the block.
    private func draw(_ lines: [String]) {
        write(ProgressRenderer.frame(lines: lines, hidesCursor: false))
    }

    /// Erases the block the prompt was drawn in.
    private func clear() {
        write(ProgressRenderer.clearBelow)
    }

    /// Prints a line above the prompt area, for notes and assembled commands.
    func note(_ text: String) {
        write(ProgressRenderer.clearBelow + text + "\n")
    }
}
