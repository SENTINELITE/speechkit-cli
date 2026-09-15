import ArgumentParser
import Foundation

/// What `stats --by` groups rows by.
public enum StatsGrouping: String, Sendable, CaseIterable, ExpressibleByArgument {
    /// One row per provider.
    case provider
    /// One row per command.
    case command
    /// One row per calendar day.
    case day
}

/// Summarises the local run history.
public struct Stats: AsyncParsableCommand {
    /// The command configuration.
    public static let configuration = CommandConfiguration(
        commandName: "stats",
        abstract: "Summarise recorded runs: audio, wall time, realtime factor, words, failures.",
        discussion: """
        Every transcribe, bench, and 'keys check --live' run is recorded locally in \
        ~/Library/Application Support/speechkit/history.jsonl unless --no-history or \
        SPEECHKIT_NO_HISTORY says otherwise. Transcript text is never recorded. \
        Realtime factors are computed from the totals, not averaged over the rows.
        """
    )

    /// How far back to look.
    @Option(name: .long, help: "Only count runs since 24h, 7d, 30d, or a date such as 2026-09-01.")
    public var since: String?

    /// What to group the rows by.
    @Option(name: .long, help: "Group rows by provider, command, or day.")
    public var by: StatsGrouping?

    /// Emits an object instead of a table.
    @Flag(name: .long, help: "Emit JSON instead of a table.")
    public var json: Bool = false

    /// Global verbosity flags.
    @OptionGroup public var globals: GlobalOptions

    /// Creates an empty command.
    public init() {}

    /// Runs the command.
    public func run() async throws {
        let console = globals.console
        let store = HistoryStore()
        let result = try await store.read()
        if result.skippedLines > 0 {
            console.warning("skipped \(result.skippedLines) unreadable line(s) in \(store.fileURL.path).")
        }

        let cutoff = try since.map { try HistoryReport.since($0) }
        let records = HistoryReport.filter(result.records, since: cutoff)

        if records.isEmpty, !json {
            print(HistoryReport.emptyMessage)
            return
        }

        let text: String
        if json {
            text = try HistoryReport.json(HistoryReport.statsDocument(records))
        } else {
            switch by {
            case .provider:
                text = HistoryReport.providerTable(records)
            case .command:
                text = HistoryReport.commandTable(records)
            case .day:
                text = HistoryReport.dayTable(records)
            case nil:
                text = HistoryReport.summary(records)
            }
        }
        console.writeStandardOutput(text)
    }
}
