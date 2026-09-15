import Foundation

/// Filters, groups, and renders recorded runs.
///
/// Everything here is a pure function over `[HistoryRecord]`, so the tables are
/// tested as golden strings against fixture records with no file and no clock.
public enum HistoryReport {
    // MARK: - Aggregates

    /// The totals over a set of records.
    public struct Totals: Sendable, Equatable, Encodable {
        /// How many records there are.
        public var runs: Int
        /// How many distinct input files they name.
        public var files: Int
        /// How many records failed.
        public var failures: Int
        /// The audio duration, in seconds, of the records that report one.
        public var audioSeconds: Double
        /// The wall time, in seconds.
        public var wallSeconds: Double
        /// The words of transcript.
        public var words: Int
        /// The characters of transcript.
        public var chars: Int

        /// Total audio seconds divided by total wall seconds.
        ///
        /// The factor is computed from the totals rather than averaged over the
        /// rows, because averaging factors weights a two-second clip the same
        /// as a two-hour recording.
        public var realtimeFactor: Double? {
            guard audioSeconds > 0, wallSeconds > 0 else { return nil }
            return audioSeconds / wallSeconds
        }

        private enum CodingKeys: String, CodingKey {
            case runs, files, failures, audioSeconds, wallSeconds, words, chars, realtimeFactor
        }

        /// Encodes the totals with the derived factor included.
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(runs, forKey: .runs)
            try container.encode(files, forKey: .files)
            try container.encode(failures, forKey: .failures)
            try container.encode(audioSeconds, forKey: .audioSeconds)
            try container.encode(wallSeconds, forKey: .wallSeconds)
            try container.encode(words, forKey: .words)
            try container.encode(chars, forKey: .chars)
            try container.encodeIfPresent(realtimeFactor, forKey: .realtimeFactor)
        }
    }

    /// Returns the totals over a set of records.
    public static func totals(_ records: [HistoryRecord]) -> Totals {
        Totals(
            runs: records.count,
            files: Set(records.map(\.fileIdentity)).count,
            failures: records.filter { !$0.succeeded }.count,
            audioSeconds: records.compactMap(\.audioSeconds).reduce(0, +),
            wallSeconds: records.map(\.wallSeconds).reduce(0, +),
            words: records.map(\.words).reduce(0, +),
            chars: records.map(\.chars).reduce(0, +)
        )
    }

    /// One row of `stats --by provider`.
    public struct ProviderStat: Sendable, Equatable, Encodable {
        /// The provider name.
        public var provider: String
        /// The totals for it.
        public var totals: Totals

        private enum CodingKeys: String, CodingKey {
            case provider, runs, files, failures, audioSeconds, wallSeconds, words, realtimeFactor
        }

        /// Encodes the row flat, so every key is one column of the table.
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(provider, forKey: .provider)
            try container.encode(totals.runs, forKey: .runs)
            try container.encode(totals.files, forKey: .files)
            try container.encode(totals.failures, forKey: .failures)
            try container.encode(totals.audioSeconds, forKey: .audioSeconds)
            try container.encode(totals.wallSeconds, forKey: .wallSeconds)
            try container.encode(totals.words, forKey: .words)
            try container.encodeIfPresent(totals.realtimeFactor, forKey: .realtimeFactor)
        }

        /// Creates a row.
        public init(provider: String, totals: Totals) {
            self.provider = provider
            self.totals = totals
        }
    }

    /// One row of `stats --by command` or `stats --by day`.
    public struct KeyedStat: Sendable, Equatable {
        /// The provider name, command name, or day.
        public var key: String
        /// The totals for it.
        public var totals: Totals

        /// Creates a row.
        public init(key: String, totals: Totals) {
            self.key = key
            self.totals = totals
        }
    }

    /// Returns one row per provider, most used first.
    public static func byProvider(_ records: [HistoryRecord]) -> [ProviderStat] {
        group(records, by: \.provider)
            .map { ProviderStat(provider: $0.key, totals: $0.totals) }
    }

    /// Returns one row per command, most used first.
    public static func byCommand(_ records: [HistoryRecord]) -> [KeyedStat] {
        group(records, by: \.command)
    }

    /// Returns one row per calendar day, oldest first.
    ///
    /// - Parameters:
    ///   - records: The records to group.
    ///   - calendar: The calendar the day boundaries come from. Tests pin it to
    ///     UTC so a golden table does not move with the machine.
    public static func byDay(_ records: [HistoryRecord], calendar: Calendar = .current) -> [KeyedStat] {
        let keyed = Dictionary(grouping: records) { dayString($0.timestamp, calendar: calendar) }
        return keyed
            .map { KeyedStat(key: $0.key, totals: totals($0.value)) }
            .sorted { $0.key < $1.key }
    }

    private static func group(_ records: [HistoryRecord], by key: KeyPath<HistoryRecord, String>) -> [KeyedStat] {
        let keyed = Dictionary(grouping: records) { $0[keyPath: key] }
        return keyed
            .map { KeyedStat(key: $0.key, totals: totals($0.value)) }
            .sorted { left, right in
                left.totals.runs == right.totals.runs
                    ? left.key < right.key
                    : left.totals.runs > right.totals.runs
            }
    }

    // MARK: - Filtering

    /// Returns the records that pass every filter, oldest first.
    ///
    /// - Parameters:
    ///   - records: Every recorded run.
    ///   - since: The earliest timestamp to keep, or `nil` for all of them.
    ///   - provider: A provider name to keep, case insensitively.
    ///   - failedOnly: Whether to drop the runs that succeeded.
    public static func filter(
        _ records: [HistoryRecord],
        since: Date? = nil,
        provider: String? = nil,
        failedOnly: Bool = false
    ) -> [HistoryRecord] {
        let wanted = provider?.lowercased()
        return records.filter { record in
            if let since, record.timestamp < since { return false }
            if let wanted, record.provider.lowercased() != wanted { return false }
            if failedOnly, record.succeeded { return false }
            return true
        }
    }

    /// Returns the date a `--since` value names.
    ///
    /// Accepted forms are `<n>h`, `<n>d`, `<n>w`, and a `yyyy-MM-dd` date,
    /// which means the start of that day in the local time zone.
    ///
    /// - Throws: ``CLIError/usage(_:)`` for anything else.
    public static func since(_ text: String, now: Date = Date(), calendar: Calendar = .current) throws -> Date {
        let value = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !value.isEmpty else { throw sinceError(text) }

        if let unit = value.last, let seconds = secondsPerUnit[unit] {
            let number = String(value.dropLast())
            guard let count = Double(number), count > 0, count.isFinite else { throw sinceError(text) }
            return now.addingTimeInterval(-count * seconds)
        }

        var components = DateComponents()
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]), parts[0].count == 4,
              let month = Int(parts[1]), (1...12).contains(month),
              let day = Int(parts[2]), (1...31).contains(day) else {
            throw sinceError(text)
        }
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else { throw sinceError(text) }
        return calendar.startOfDay(for: date)
    }

    private static let secondsPerUnit: [Character: Double] = [
        "h": 3600,
        "d": 86_400,
        "w": 604_800
    ]

    private static func sinceError(_ text: String) -> CLIError {
        CLIError.usage("--since '\(text)' is not a duration or a date. Use 24h, 7d, 30d, or 2026-09-01.")
    }

    // MARK: - Summary

    /// The line `stats` prints when there is nothing recorded.
    public static let emptyMessage = "No history yet. Runs are recorded after the first transcription."

    /// The width every summary label is padded to.
    static let labelWidth = 22

    /// Renders the default `stats` output.
    ///
    /// - Parameters:
    ///   - records: The records in range, in any order.
    ///   - now: The clock, for the span in days.
    ///   - calendar: The calendar the day span is counted in.
    public static func summary(_ records: [HistoryRecord], now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let earliest = records.map(\.timestamp).min() else { return emptyMessage + "\n" }
        let sums = totals(records)

        let days = max(
            1,
            (calendar.dateComponents([.day], from: calendar.startOfDay(for: earliest), to: calendar.startOfDay(for: now)).day ?? 0) + 1
        )
        var lines = [
            "Since \(dayString(earliest, calendar: calendar)) (\(plural(days, "day"))), "
                + "\(plural(sums.runs, "run")), \(plural(sums.files, "file")), \(plural(sums.failures, "failure"))"
        ]
        lines.append(row("Audio transcribed", sums.audioSeconds > 0 ? duration(sums.audioSeconds) : "-"))
        lines.append(row("Wall time", duration(sums.wallSeconds)))
        lines.append(row("Realtime factor", realtime(sums.realtimeFactor)))
        lines.append(row("Words", count(sums.words)))

        let commands = byCommand(records)
        if !commands.isEmpty {
            lines.append(row("Most used commands", commands.prefix(5).map { "\($0.key) \($0.totals.runs)" }.joined(separator: ", ")))
        }
        let providers = byProvider(records)
        if !providers.isEmpty {
            lines.append(row("Most used providers", providers.prefix(5).map { "\($0.provider) \($0.totals.runs)" }.joined(separator: ", ")))
        }

        let ranked = providers
            .compactMap { stat in stat.totals.realtimeFactor.map { (stat.provider, $0) } }
            .sorted { $0.1 > $1.1 }
        if let fastest = ranked.first {
            var line = row("Fastest provider", "\(fastest.0) \(realtime(fastest.1))")
            if let slowest = ranked.last, ranked.count > 1 {
                line += "   Slowest  \(slowest.0) \(realtime(slowest.1))"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func row(_ label: String, _ value: String) -> String {
        label.padding(toLength: max(labelWidth, label.count + 1), withPad: " ", startingAt: 0) + value
    }

    private static func plural(_ value: Int, _ noun: String) -> String {
        "\(count(value)) \(noun)\(value == 1 ? "" : "s")"
    }

    // MARK: - Tables

    /// Renders `stats --by provider`.
    public static func providerTable(_ records: [HistoryRecord]) -> String {
        let rows = byProvider(records).map { stat in
            [
                stat.provider,
                count(stat.totals.runs),
                count(stat.totals.files),
                stat.totals.audioSeconds > 0 ? duration(stat.totals.audioSeconds) : "-",
                duration(stat.totals.wallSeconds),
                realtime(stat.totals.realtimeFactor),
                count(stat.totals.words),
                count(stat.totals.failures)
            ]
        }
        return TextTable(
            headers: ["provider", "runs", "files", "audio", "wall", "realtime", "words", "failures"],
            rows: rows
        ).render()
    }

    /// Renders `stats --by command`.
    public static func commandTable(_ records: [HistoryRecord]) -> String {
        let rows = byCommand(records).map { stat in
            [
                stat.key,
                count(stat.totals.runs),
                count(stat.totals.files),
                duration(stat.totals.wallSeconds),
                count(stat.totals.failures)
            ]
        }
        return TextTable(headers: ["command", "runs", "files", "wall", "failures"], rows: rows).render()
    }

    /// Renders `stats --by day`.
    public static func dayTable(_ records: [HistoryRecord], calendar: Calendar = .current) -> String {
        let rows = byDay(records, calendar: calendar).map { stat in
            [
                stat.key,
                count(stat.totals.runs),
                count(stat.totals.files),
                stat.totals.audioSeconds > 0 ? duration(stat.totals.audioSeconds) : "-",
                duration(stat.totals.wallSeconds),
                realtime(stat.totals.realtimeFactor),
                count(stat.totals.words)
            ]
        }
        return TextTable(
            headers: ["day", "runs", "files", "audio", "wall", "realtime", "words"],
            rows: rows
        ).render()
    }

    /// Renders the `history` table, newest first.
    ///
    /// - Parameters:
    ///   - records: The records to show, oldest first.
    ///   - limit: How many rows to keep, counting from the newest.
    ///   - timeZone: The zone the `WHEN` column is written in.
    public static func historyTable(
        _ records: [HistoryRecord],
        limit: Int,
        timeZone: TimeZone = .current
    ) -> String {
        let newestFirst = records.sorted { $0.timestamp > $1.timestamp }.prefix(max(limit, 0))
        let rows = newestFirst.map { record in
            [
                minuteString(record.timestamp, timeZone: timeZone),
                record.command,
                record.provider,
                record.fileName,
                record.audioSeconds.map(duration) ?? "-",
                duration(record.wallSeconds),
                realtime(record.realtimeFactor),
                count(record.words),
                record.succeeded ? "ok" : record.status
            ]
        }
        return TextTable(
            headers: ["when", "command", "provider", "file", "audio", "wall", "realtime", "words", "status"],
            rows: rows
        ).render()
    }

    // MARK: - JSON

    /// The `stats --json` document.
    public struct StatsDocument: Sendable, Encodable {
        /// The timestamp of the earliest record in range.
        public var since: String?
        /// How many calendar days the range spans.
        public var spanDays: Int
        /// The totals over every record in range.
        public var totals: Totals
        /// One entry per command.
        public var commands: [String: Totals]
        /// One entry per provider.
        public var providers: [String: Totals]
        /// One entry per day, keyed `yyyy-MM-dd`.
        public var days: [String: Totals]
    }

    /// Builds the `stats --json` document.
    public static func statsDocument(
        _ records: [HistoryRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> StatsDocument {
        let earliest = records.map(\.timestamp).min()
        let spanDays = earliest.map { first in
            max(1, (calendar.dateComponents([.day], from: calendar.startOfDay(for: first), to: calendar.startOfDay(for: now)).day ?? 0) + 1)
        } ?? 0
        return StatsDocument(
            since: earliest.map { HistoryRecord.timestampFormatter.string(from: $0) },
            spanDays: spanDays,
            totals: totals(records),
            commands: Dictionary(uniqueKeysWithValues: byCommand(records).map { ($0.key, $0.totals) }),
            providers: Dictionary(uniqueKeysWithValues: byProvider(records).map { ($0.provider, $0.totals) }),
            days: Dictionary(uniqueKeysWithValues: byDay(records, calendar: calendar).map { ($0.key, $0.totals) })
        )
    }

    /// Encodes a value as pretty JSON with sorted keys and a trailing newline.
    ///
    /// - Throws: Any error raised while encoding.
    public static func json(_ value: some Encodable) throws -> String {
        let encoder = HistoryRecord.encoder
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self) + "\n"
    }

    // MARK: - Formatting

    /// Returns a duration as `6 h 12 m`, `4 m 51 s`, or `12.3 s`.
    public static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0.0 s" }
        let whole = Int(seconds.rounded())
        if whole >= 3600 { return "\(whole / 3600) h \((whole % 3600) / 60) m" }
        if whole >= 60 { return "\(whole / 60) m \(whole % 60) s" }
        return String(format: "%.1f s", seconds)
    }

    /// Returns a count with thousands separators.
    public static func count(_ value: Int) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// Returns a realtime factor as `141x` or `9.8x`, or `-` when there is none.
    public static func realtime(_ factor: Double?) -> String {
        guard let factor, factor.isFinite, factor > 0 else { return "-" }
        return factor >= 100 ? String(format: "%.0fx", factor) : String(format: "%.1fx", factor)
    }

    /// Returns a date as `yyyy-MM-dd`.
    public static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// Returns a date as `yyyy-MM-dd HH:mm`.
    public static func minuteString(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "%04d-%02d-%02d %02d:%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0
        )
    }

    /// Groups digits the same way whatever the machine's locale is.
    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return formatter
    }()
}
