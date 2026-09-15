import Foundation

/// One benchmarked run: one input file through one provider.
///
/// A failed row carries the file, the provider, and a ``status`` holding the
/// error, and leaves every measurement `nil`. The CSV and Markdown renderers
/// print an empty cell for a `nil`, so a failure never contributes a zero to a
/// column someone might average.
public struct BenchRow: Sendable, Codable, Equatable {
    /// The input file name, without its directory.
    public var file: String
    /// The `--provider` value the row was produced by.
    public var provider: String
    /// The model the provider reported, when it names one.
    public var model: String?
    /// The audio duration, in seconds.
    public var audioSeconds: Double?
    /// The mean wall time of the provider call, in seconds, over the repeats.
    public var wallSeconds: Double?
    /// The fastest of the repeats, in seconds.
    public var wallMinSeconds: Double?
    /// Audio seconds divided by mean wall seconds.
    public var realtimeFactor: Double?
    /// The compute time the provider reported, in seconds.
    public var processingSeconds: Double?
    /// The billable audio seconds the provider reported.
    public var billedSeconds: Double?
    /// The total tokens the provider reported.
    public var totalTokens: Int?
    /// The characters of transcript text.
    public var chars: Int?
    /// The words of transcript text.
    public var words: Int?
    /// A rough token count, `ceil(chars / 4)`, for providers that report none.
    public var estimatedTokens: Int?
    /// The bytes the plain-text transcript occupies.
    public var bytes: Int?
    /// The number of segments in the transcript.
    public var segments: Int?
    /// Whether the transcript carries word-level timings.
    public var hasWordTimings: Bool?
    /// The word error rate against the reference, when there was one.
    public var wer: Double?
    /// `ok`, or the error that failed the row.
    public var status: String

    /// The column order used by the CSV, the Markdown table, and the JSON keys.
    private enum CodingKeys: String, CodingKey {
        case file
        case provider
        case model
        case audioSeconds = "audio_seconds"
        case wallSeconds = "wall_seconds"
        case wallMinSeconds = "wall_min_seconds"
        case realtimeFactor = "realtime_factor"
        case processingSeconds = "processing_seconds"
        case billedSeconds = "billed_seconds"
        case totalTokens = "total_tokens"
        case chars
        case words
        case estimatedTokens = "est_tokens"
        case bytes
        case segments
        case hasWordTimings = "has_word_timings"
        case wer
        case status
    }

    /// The status every successful row carries.
    public static let okStatus = "ok"

    /// Creates a row.
    public init(
        file: String,
        provider: String,
        model: String? = nil,
        audioSeconds: Double? = nil,
        wallSeconds: Double? = nil,
        wallMinSeconds: Double? = nil,
        realtimeFactor: Double? = nil,
        processingSeconds: Double? = nil,
        billedSeconds: Double? = nil,
        totalTokens: Int? = nil,
        chars: Int? = nil,
        words: Int? = nil,
        estimatedTokens: Int? = nil,
        bytes: Int? = nil,
        segments: Int? = nil,
        hasWordTimings: Bool? = nil,
        wer: Double? = nil,
        status: String = BenchRow.okStatus
    ) {
        self.file = file
        self.provider = provider
        self.model = model
        self.audioSeconds = audioSeconds
        self.wallSeconds = wallSeconds
        self.wallMinSeconds = wallMinSeconds
        self.realtimeFactor = realtimeFactor
        self.processingSeconds = processingSeconds
        self.billedSeconds = billedSeconds
        self.totalTokens = totalTokens
        self.chars = chars
        self.words = words
        self.estimatedTokens = estimatedTokens
        self.bytes = bytes
        self.segments = segments
        self.hasWordTimings = hasWordTimings
        self.wer = wer
        self.status = status
    }

    /// A Boolean value indicating whether the run behind the row succeeded.
    public var succeeded: Bool {
        status == Self.okStatus
    }

    /// The estimated token count for a transcript of `chars` characters.
    ///
    /// Four characters to a token is the rule of thumb every tokenizer roughly
    /// agrees with for English prose and none of them agrees with exactly. The
    /// column is named `est_tokens` for that reason; `total_tokens` beside it
    /// carries the provider's own count when there is one.
    public static func estimatedTokens(forCharacters count: Int) -> Int {
        Int((Double(count) / 4).rounded(.up))
    }
}

/// What one provider did over the whole benchmark.
public struct BenchProviderSummary: Sendable, Codable, Equatable {
    /// The `--provider` value.
    public var provider: String
    /// How many files the provider was given.
    public var files: Int
    /// How many of them failed.
    public var failures: Int
    /// The audio seconds of the files that succeeded.
    public var audioSeconds: Double
    /// The wall seconds those files took.
    public var wallSeconds: Double
    /// Total audio seconds over total wall seconds.
    public var realtimeFactor: Double?
    /// The mean word error rate over the files that had a reference.
    public var meanWER: Double?
    /// What preparing the provider cost before the first file.
    ///
    /// Only the on-device models spend anything here. VOZ loads a Core ML model
    /// once per provider pass, and that load is deliberately outside the
    /// per-file timings, so it is reported here instead of inflating the first
    /// file's wall time.
    public var setupSeconds: Double?

    private enum CodingKeys: String, CodingKey {
        case provider
        case files
        case failures
        case audioSeconds = "audio_seconds"
        case wallSeconds = "wall_seconds"
        case realtimeFactor = "realtime_factor"
        case meanWER = "mean_wer"
        case setupSeconds = "setup_seconds"
    }

    /// Creates a summary.
    public init(
        provider: String,
        files: Int,
        failures: Int,
        audioSeconds: Double,
        wallSeconds: Double,
        realtimeFactor: Double?,
        meanWER: Double?,
        setupSeconds: Double?
    ) {
        self.provider = provider
        self.files = files
        self.failures = failures
        self.audioSeconds = audioSeconds
        self.wallSeconds = wallSeconds
        self.realtimeFactor = realtimeFactor
        self.meanWER = meanWER
        self.setupSeconds = setupSeconds
    }

    /// Aggregates the rows of one provider.
    ///
    /// - Parameters:
    ///   - rows: Every row for one provider.
    ///   - provider: The provider name.
    ///   - setupSeconds: What preparation cost, when it cost anything.
    public static func make(
        rows: [BenchRow],
        provider: String,
        setupSeconds: Double? = nil
    ) -> BenchProviderSummary {
        let succeeded = rows.filter(\.succeeded)
        let audio = succeeded.compactMap(\.audioSeconds).reduce(0, +)
        let wall = succeeded.compactMap(\.wallSeconds).reduce(0, +)
        let rates = succeeded.compactMap(\.wer)
        return BenchProviderSummary(
            provider: provider,
            files: rows.count,
            failures: rows.count - succeeded.count,
            audioSeconds: audio,
            wallSeconds: wall,
            realtimeFactor: wall > 0 ? audio / wall : nil,
            meanWER: rates.isEmpty ? nil : rates.reduce(0, +) / Double(rates.count),
            setupSeconds: setupSeconds
        )
    }
}

/// Everything `bench` writes: the rows, the per-provider aggregates, and the
/// three renderings of them.
public struct BenchReport: Sendable, Codable, Equatable {
    /// One row per file per provider, sorted by file then provider.
    public var rows: [BenchRow]
    /// One aggregate per provider, in the order the providers ran.
    public var providers: [BenchProviderSummary]

    /// Creates a report.
    ///
    /// Rows are sorted by file name and then provider, so the same file's
    /// transcripts sit next to each other however the run was ordered.
    public init(rows: [BenchRow], providers: [BenchProviderSummary]) {
        self.rows = rows.sorted { left, right in
            if left.file == right.file { return left.provider < right.provider }
            return left.file < right.file
        }
        self.providers = providers
    }

    /// The column headings, in order, shared by the CSV and the Markdown table.
    public static let columns = [
        "file", "provider", "model", "audio_seconds", "wall_seconds", "wall_min_seconds",
        "realtime_factor", "processing_seconds", "billed_seconds", "total_tokens",
        "chars", "words", "est_tokens", "bytes", "segments", "has_word_timings",
        "wer", "status"
    ]

    /// The columns of the per-provider aggregate table.
    public static let summaryColumns = [
        "provider", "files", "failures", "audio_seconds", "wall_seconds",
        "realtime_factor", "mean_wer", "setup_seconds"
    ]

    /// The longest error a Markdown or CSV cell carries before it is cut short.
    ///
    /// `summary.json` keeps the whole message, so nothing is lost; the tables
    /// stay readable.
    public static let statusLimit = 60

    /// The cells of one row, in ``columns`` order.
    static func cells(for row: BenchRow, statusLimit: Int?) -> [String] {
        [
            row.file,
            row.provider,
            row.model ?? "",
            decimal(row.audioSeconds, places: 2),
            decimal(row.wallSeconds, places: 3),
            decimal(row.wallMinSeconds, places: 3),
            decimal(row.realtimeFactor, places: 2),
            decimal(row.processingSeconds, places: 3),
            decimal(row.billedSeconds, places: 2),
            row.totalTokens.map(String.init) ?? "",
            row.chars.map(String.init) ?? "",
            row.words.map(String.init) ?? "",
            row.estimatedTokens.map(String.init) ?? "",
            row.bytes.map(String.init) ?? "",
            row.segments.map(String.init) ?? "",
            row.hasWordTimings.map { $0 ? "yes" : "no" } ?? "",
            decimal(row.wer, places: 3),
            statusLimit.map { truncate(row.status, to: $0) } ?? row.status
        ]
    }

    /// The cells of one aggregate, in ``summaryColumns`` order.
    static func cells(for summary: BenchProviderSummary) -> [String] {
        [
            summary.provider,
            String(summary.files),
            String(summary.failures),
            decimal(summary.audioSeconds, places: 2),
            decimal(summary.wallSeconds, places: 3),
            decimal(summary.realtimeFactor, places: 2),
            decimal(summary.meanWER, places: 3),
            decimal(summary.setupSeconds, places: 2)
        ]
    }

    /// Renders the rows as RFC 4180 comma-separated values.
    ///
    /// Every cell that carries a comma, a quote, or a line break is quoted and
    /// its quotes doubled, so an error message with a comma in it cannot shift
    /// the columns of a spreadsheet.
    public func csv() -> String {
        var lines = [Self.columns.map(Self.escapeCSV).joined(separator: ",")]
        lines += rows.map { row in
            Self.cells(for: row, statusLimit: Self.statusLimit)
                .map(Self.escapeCSV)
                .joined(separator: ",")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Renders the rows and the aggregates as GitHub-flavoured Markdown.
    public func markdown() -> String {
        var text = "# Benchmark\n\n"
        text += Self.markdownTable(
            headers: Self.columns,
            rows: rows.map { Self.cells(for: $0, statusLimit: Self.statusLimit) }
        )
        text += "\n## Providers\n\n"
        text += Self.markdownTable(
            headers: Self.summaryColumns,
            rows: providers.map(Self.cells(for:))
        )
        return text
    }

    /// Renders the whole report as JSON, with the untruncated error messages.
    ///
    /// - Throws: Any encoding failure.
    public func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self) + "\n"
    }

    /// Renders the per-provider aggregates as the plain table printed to stdout.
    public func providerTable() -> String {
        TextTable(
            headers: Self.summaryColumns,
            rows: providers.map(Self.cells(for:))
        ).render()
    }

    /// Renders one Markdown table, left-aligned, with padded cells.
    static func markdownTable(headers: [String], rows: [[String]]) -> String {
        let escapedRows = rows.map { $0.map(escapeMarkdown) }
        var widths = headers.map(\.count)
        for row in escapedRows {
            for (index, cell) in row.enumerated() where index < widths.count {
                widths[index] = max(widths[index], cell.count)
            }
        }

        func line(_ cells: [String]) -> String {
            let padded = cells.enumerated().map { index, cell in
                cell.padding(toLength: widths[index], withPad: " ", startingAt: 0)
            }
            return "| " + padded.joined(separator: " | ") + " |\n"
        }

        var text = line(headers)
        text += "| " + widths.map { String(repeating: "-", count: $0) }.joined(separator: " | ") + " |\n"
        for row in escapedRows { text += line(row) }
        return text
    }

    /// Returns a number with a fixed number of decimal places, or a blank cell.
    static func decimal(_ value: Double?, places: Int) -> String {
        guard let value, value.isFinite else { return "" }
        return String(format: "%.\(places)f", value)
    }

    /// Returns a CSV cell, quoted when it has to be.
    static func escapeCSV(_ cell: String) -> String {
        guard cell.contains(",") || cell.contains("\"") || cell.contains("\n") || cell.contains("\r") else {
            return cell
        }
        return "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Returns a Markdown cell with the characters that would break a table neutralised.
    static func escapeMarkdown(_ cell: String) -> String {
        cell.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    /// Returns text cut to a length, with an ellipsis when anything was cut.
    static func truncate(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit - 1)) + "\u{2026}"
    }
}
