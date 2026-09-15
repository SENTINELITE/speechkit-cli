import ArgumentParser
import Darwin
import Foundation

/// Lists recorded runs, newest first.
public struct History: AsyncParsableCommand {
    /// The command configuration.
    public static let configuration = CommandConfiguration(
        commandName: "history",
        abstract: "List recorded runs, newest first.",
        subcommands: [Clear.self]
    )

    /// How many rows to print.
    @Option(name: .long, help: "How many rows to print.")
    public var limit: Int = 20

    /// Keeps only one provider's rows.
    @Option(name: [.customShort("p"), .long], help: "Only rows for this provider.")
    public var provider: String?

    /// Keeps only the runs that failed.
    @Flag(name: .long, help: "Only rows that failed.")
    public var failed: Bool = false

    /// How far back to look.
    @Option(name: .long, help: "Only rows since 24h, 7d, 30d, or a date such as 2026-09-01.")
    public var since: String?

    /// Emits an array of objects instead of a table.
    @Flag(name: .long, help: "Emit JSON instead of a table.")
    public var json: Bool = false

    /// Global verbosity flags.
    @OptionGroup public var globals: GlobalOptions

    /// Creates an empty command.
    public init() {}

    /// Checks the flags.
    public func validate() throws {
        guard limit > 0 else {
            throw ValidationError("--limit must be at least 1.")
        }
    }

    /// Runs the command.
    public func run() async throws {
        let console = globals.console
        let store = HistoryStore()
        let result = try await store.read()
        if result.skippedLines > 0 {
            console.warning("skipped \(result.skippedLines) unreadable line(s) in \(store.fileURL.path).")
        }

        let cutoff = try since.map { try HistoryReport.since($0) }
        let records = HistoryReport.filter(
            result.records,
            since: cutoff,
            provider: provider,
            failedOnly: failed
        )
        if records.isEmpty, !json {
            print(HistoryReport.emptyMessage)
            return
        }

        if json {
            let newest = Array(records.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
            console.writeStandardOutput(try HistoryReport.json(newest))
        } else {
            console.writeStandardOutput(HistoryReport.historyTable(records, limit: limit))
        }
    }

    /// Deletes the history file.
    public struct Clear: AsyncParsableCommand {
        /// The command configuration.
        public static let configuration = CommandConfiguration(
            commandName: "clear",
            abstract: "Delete the local usage history after a confirmation."
        )

        /// Skips the confirmation.
        @Flag(name: [.customShort("y"), .long], help: "Delete without asking.")
        public var yes: Bool = false

        /// Global verbosity flags.
        @OptionGroup public var globals: GlobalOptions

        /// Creates an empty command.
        public init() {}

        /// Runs the command.
        public func run() async throws {
            let store = HistoryStore()
            guard await store.exists else {
                print("No history to clear.")
                return
            }
            let runs = try await store.read().records.count

            let prompt = "Delete \(HistoryReport.count(runs)) recorded run(s) from \(store.fileURL.path)? [y/N] "
            guard try History.confirm(
                yes: yes,
                isStandardInputTTY: isatty(FileHandle.standardInput.fileDescriptor) == 1,
                prompt: prompt
            ) else {
                print("Nothing was deleted.")
                return
            }

            try await store.clear()
            print("Deleted \(store.fileURL.path).")
        }
    }

    /// Returns whether the history should be deleted.
    ///
    /// A pipe cannot answer a question, so a scripted `history clear` without
    /// `--yes` is refused rather than silently confirmed or silently skipped.
    ///
    /// - Parameters:
    ///   - yes: Whether `--yes` was passed.
    ///   - isStandardInputTTY: Whether there is anyone to ask.
    ///   - prompt: The question.
    ///   - readAnswer: Where the answer comes from. Tests substitute it.
    /// - Throws: ``CLIError/usage(_:)`` when there is no terminal and no `--yes`.
    public static func confirm(
        yes: Bool,
        isStandardInputTTY: Bool,
        prompt: String,
        readAnswer: () -> String? = { readLine(strippingNewline: true) }
    ) throws -> Bool {
        if yes { return true }
        guard isStandardInputTTY else {
            throw CLIError.usage("Pass --yes to clear the history when standard input is not a terminal.")
        }
        Console.writeStandardError(prompt)
        let answer = (readAnswer() ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return answer == "y" || answer == "yes"
    }
}
