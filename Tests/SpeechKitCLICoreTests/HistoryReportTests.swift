import Foundation
import Testing
@testable import SpeechKitCLICore

/// Filtering, grouping, and rendering recorded runs.
@Suite("History report")
struct HistoryReportTests {
    /// A UTC calendar, so a golden day table does not move with the machine.
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static func date(_ text: String) -> Date {
        guard let date = HistoryRecord.plainTimestampFormatter.date(from: text) else {
            fatalError("bad fixture date \(text)")
        }
        return date
    }

    static func record(
        _ timestamp: String,
        command: String = "transcribe",
        provider: String,
        file: String,
        audio: Double?,
        wall: Double,
        words: Int,
        status: String = HistoryStatus.ok
    ) -> HistoryRecord {
        HistoryRecord(
            timestamp: date(timestamp),
            cliVersion: "0.7.0",
            command: command,
            provider: provider,
            fileName: file,
            audioSeconds: audio,
            wallSeconds: wall,
            words: words,
            chars: words * 6,
            formats: ["txt"],
            status: status
        )
    }

    /// Four runs over two days, three providers, and one failure.
    ///
    /// The two VOZ rows run at 120x and 60x, so a factor averaged over the rows
    /// would read 90x where the totals read 68.6x.
    static let fixtures: [HistoryRecord] = [
        record("2026-09-13T10:00:00Z", provider: "voz", file: "talk.wav", audio: 600, wall: 5, words: 1_200),
        record("2026-09-13T11:00:00Z", provider: "voz", file: "interview.wav", audio: 1_800, wall: 30, words: 3_000),
        record("2026-09-14T09:00:00Z", provider: "apple", file: "talk.wav", audio: 600, wall: 60, words: 1_100),
        record(
            "2026-09-14T09:30:00Z",
            command: "bench",
            provider: "grok",
            file: "talk.wav",
            audio: nil,
            wall: 120,
            words: 0,
            status: HistoryStatus.provider
        )
    ]

    // MARK: - Totals

    @Test("the realtime factor comes from the totals, not from an average of factors")
    func realtimeFromTotals() throws {
        let voz = HistoryReport.byProvider(Self.fixtures).first { $0.provider == "voz" }
        let factor = try #require(voz?.totals.realtimeFactor)

        #expect(abs(factor - 2_400 / 35) < 0.001)
        #expect(HistoryReport.realtime(factor) == "68.6x")
        // The average of the two row factors would be 90x.
        #expect(abs(factor - 90) > 1)
    }

    @Test("totals count distinct files, failures, and sums")
    func totals() {
        let totals = HistoryReport.totals(Self.fixtures)
        #expect(totals.runs == 4)
        #expect(totals.files == 2)
        #expect(totals.failures == 1)
        #expect(totals.audioSeconds == 3_000)
        #expect(totals.wallSeconds == 215)
        #expect(totals.words == 5_300)
    }

    // MARK: - Formatting

    @Test("durations read as hours, minutes, or seconds")
    func durations() {
        #expect(HistoryReport.duration(22_320) == "6 h 12 m")
        #expect(HistoryReport.duration(291) == "4 m 51 s")
        #expect(HistoryReport.duration(12.34) == "12.3 s")
        #expect(HistoryReport.duration(59.96) == "1 m 0 s")
        #expect(HistoryReport.duration(0) == "0.0 s")
    }

    @Test("counts carry thousands separators and factors carry an x")
    func numbers() {
        #expect(HistoryReport.count(58_310) == "58,310")
        #expect(HistoryReport.count(7) == "7")
        #expect(HistoryReport.realtime(141.2) == "141x")
        #expect(HistoryReport.realtime(9.83) == "9.8x")
        #expect(HistoryReport.realtime(nil) == "-")
        #expect(HistoryReport.realtime(0) == "-")
    }

    // MARK: - Since

    @Test("--since takes hours, days, weeks, and a date")
    func sinceParsing() throws {
        let now = Self.date("2026-09-15T12:00:00Z")
        #expect(try HistoryReport.since("24h", now: now) == Self.date("2026-09-14T12:00:00Z"))
        #expect(try HistoryReport.since("7d", now: now) == Self.date("2026-09-08T12:00:00Z"))
        #expect(try HistoryReport.since("2w", now: now) == Self.date("2026-09-01T12:00:00Z"))
        #expect(
            try HistoryReport.since("2026-09-01", now: now, calendar: Self.utc)
                == Self.date("2026-09-01T00:00:00Z")
        )
    }

    @Test("an unparseable --since is a usage error")
    func sinceRejectsNonsense() {
        for value in ["", "yesterday", "7", "-3d", "0d", "d", "2026-13-01", "2026-09"] {
            #expect(throws: CLIError.self, "'\(value)' should be rejected") {
                _ = try HistoryReport.since(value)
            }
        }
    }

    @Test("--since keeps only the records at or after the cutoff")
    func sinceFilters() {
        let kept = HistoryReport.filter(Self.fixtures, since: Self.date("2026-09-14T00:00:00Z"))
        #expect(kept.map(\.provider) == ["apple", "grok"])
    }

    @Test("history filters combine provider and failures")
    func historyFilters() {
        #expect(HistoryReport.filter(Self.fixtures, provider: "VOZ").count == 2)
        #expect(HistoryReport.filter(Self.fixtures, failedOnly: true).map(\.provider) == ["grok"])
        #expect(HistoryReport.filter(Self.fixtures, provider: "apple", failedOnly: true).isEmpty)
    }

    // MARK: - Tables

    @Test("stats --by provider ranks providers by runs")
    func providerTable() {
        #expect(HistoryReport.providerTable(Self.fixtures) == """
        PROVIDER  RUNS  FILES  AUDIO     WALL     REALTIME  WORDS  FAILURES
        voz       2     2      40 m 0 s  35.0 s   68.6x     4,200  0
        apple     1     1      10 m 0 s  1 m 0 s  10.0x     1,100  0
        grok      1     1      -         2 m 0 s  -         0      1

        """)
    }

    @Test("stats --by command counts runs, files, wall time, and failures")
    func commandTable() {
        #expect(HistoryReport.commandTable(Self.fixtures) == """
        COMMAND     RUNS  FILES  WALL      FAILURES
        transcribe  3     2      1 m 35 s  0
        bench       1     1      2 m 0 s   1

        """)
    }

    @Test("stats --by day gives one row per day, oldest first")
    func dayTable() {
        #expect(HistoryReport.dayTable(Self.fixtures, calendar: Self.utc) == """
        DAY         RUNS  FILES  AUDIO     WALL     REALTIME  WORDS
        2026-09-13  2     2      40 m 0 s  35.0 s   68.6x     4,200
        2026-09-14  2     1      10 m 0 s  3 m 0 s  3.3x      1,100

        """)
    }

    @Test("history lists the newest rows first, capped at the limit")
    func historyTable() {
        let text = HistoryReport.historyTable(
            Self.fixtures,
            limit: 2,
            timeZone: TimeZone(identifier: "UTC")!
        )
        #expect(text == """
        WHEN              COMMAND     PROVIDER  FILE      AUDIO     WALL     REALTIME  WORDS  STATUS
        2026-09-14 09:30  bench       grok      talk.wav  -         2 m 0 s  -         0      provider
        2026-09-14 09:00  transcribe  apple     talk.wav  10 m 0 s  1 m 0 s  10.0x     1,100  ok

        """)
    }

    // MARK: - Summary

    @Test("the default summary reads like a report")
    func summary() {
        let text = HistoryReport.summary(
            Self.fixtures,
            now: Self.date("2026-09-15T12:00:00Z"),
            calendar: Self.utc
        )
        #expect(text == """
        Since 2026-09-13 (3 days), 4 runs, 2 files, 1 failure
        Audio transcribed     50 m 0 s
        Wall time             3 m 35 s
        Realtime factor       14.0x
        Words                 5,300
        Most used commands    transcribe 3, bench 1
        Most used providers   voz 2, apple 1, grok 1
        Fastest provider      voz 68.6x   Slowest  apple 10.0x

        """)
    }

    @Test("an empty history says so rather than printing an empty table")
    func emptySummary() {
        #expect(HistoryReport.summary([]) == HistoryReport.emptyMessage + "\n")
    }

    // MARK: - JSON

    @Test("stats --json carries the totals and every grouping")
    func statsJSON() throws {
        let text = try HistoryReport.json(
            HistoryReport.statsDocument(Self.fixtures, now: Self.date("2026-09-15T12:00:00Z"), calendar: Self.utc)
        )
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )

        #expect(object["spanDays"] as? Int == 3)
        #expect(object["since"] as? String == "2026-09-13T10:00:00.000Z")
        let totals = try #require(object["totals"] as? [String: Any])
        #expect(totals["runs"] as? Int == 4)
        #expect(totals["failures"] as? Int == 1)
        let providers = try #require(object["providers"] as? [String: Any])
        #expect(providers.keys.sorted() == ["apple", "grok", "voz"])
        let days = try #require(object["days"] as? [String: Any])
        #expect(days.keys.sorted() == ["2026-09-13", "2026-09-14"])
    }

    // MARK: - Clearing

    @Test("history clear refuses without --yes when stdin is not a terminal")
    func clearRefusesOffATerminal() throws {
        #expect(throws: CLIError.self) {
            _ = try History.confirm(yes: false, isStandardInputTTY: false, prompt: "?")
        }
        #expect(try History.confirm(yes: true, isStandardInputTTY: false, prompt: "?"))
    }

    @Test("history clear takes y or yes from a terminal and nothing else")
    func clearReadsTheAnswer() throws {
        #expect(try History.confirm(yes: false, isStandardInputTTY: true, prompt: "?") { "y" })
        #expect(try History.confirm(yes: false, isStandardInputTTY: true, prompt: "?") { "YES" })
        #expect(try !History.confirm(yes: false, isStandardInputTTY: true, prompt: "?") { "" })
        #expect(try !History.confirm(yes: false, isStandardInputTTY: true, prompt: "?") { nil })
    }
}
