import Foundation
import Testing
@testable import SpeechKitCLICore

@Suite("Bench")
struct BenchTests {
    // MARK: Arguments

    @Test("The bench flag set parses")
    func flagSet() throws {
        let command = try Bench.parse([
            "./recordings/", "b.m4a",
            "--provider", "VOZ", "-p", "apple", "-p", "all",
            "--language", "en-US",
            "--words",
            "--diarize",
            "--format", "txt", "-f", "srt",
            "--json-transcripts",
            "--reference-dir", "./refs",
            "--recursive",
            "--no-download",
            "--overwrite",
            "--jobs", "3",
            "--repeat", "4",
            "--output", "./bench/",
            "--verbose",
        ])

        #expect(command.inputs == ["./recordings/", "b.m4a"])
        #expect(command.provider == [.one(.voz), .one(.apple), .all])
        #expect(command.language == ["en-US"])
        #expect(command.words)
        #expect(command.diarize)
        #expect(command.resolvedFormats == [.txt, .srt, .json])
        #expect(command.referenceDir == "./refs")
        #expect(command.recursive)
        #expect(command.noDownload)
        #expect(command.overwrite)
        #expect(command.jobs == 3)
        #expect(command.repeatCount == 4)
        #expect(command.output == "./bench/")
        #expect(command.globals.verbose)
    }

    @Test("The defaults are one job, one repeat, and plain text")
    func defaults() throws {
        let command = try Bench.parse(["a.wav", "-p", "apple", "-o", "/tmp/bench"])
        #expect(command.jobs == 1)
        #expect(command.repeatCount == 1)
        #expect(command.resolvedFormats == [.txt])
        #expect(!command.recursive)
        #expect(command.referenceDir == nil)
    }

    @Test("--output is required")
    func outputRequired() {
        #expect(throws: (any Error).self) {
            _ = try Bench.parse(["a.wav", "-p", "apple"])
        }
    }

    @Test("A provider is required, and so is an input")
    func requiredArguments() throws {
        #expect(throws: (any Error).self) {
            _ = try Bench.parse(["a.wav", "-o", "/tmp/bench"])
        }
        #expect(throws: (any Error).self) {
            _ = try Bench.parse(["-p", "apple", "-o", "/tmp/bench"])
        }
    }

    @Test("--repeat and --jobs must be at least one")
    func counts() throws {
        #expect(throws: (any Error).self) {
            _ = try Bench.parse(["a.wav", "-p", "apple", "-o", "/tmp/bench", "--repeat", "0"])
        }
        #expect(throws: (any Error).self) {
            _ = try Bench.parse(["a.wav", "-p", "apple", "-o", "/tmp/bench", "--jobs", "0"])
        }
    }

    @Test("The flags transcribe carries and bench does not are rejected")
    func rejectedFlags() {
        for flag in ["--api-key", "--endpoint", "--timeout", "--model", "--prompt", "--max-cue-chars"] {
            #expect(throws: (any Error).self) {
                _ = try Bench.parse(["a.wav", "-p", "apple", "-o", "/tmp/bench", flag, "1"])
            }
        }
    }

    // MARK: Provider selection

    @Test("all expands to every provider that could run here")
    func allExpansion() {
        let selection = Bench.resolveProviders([.all]) { provider in
            switch provider {
            case .apple, .voz: return .notNeeded
            case .openai: return .environment
            case .grok: return .keychain
            default: return .notFound
            }
        }
        #expect(selection.providers == [.grok, .openai, .apple, .voz])
        #expect(selection.skipped.isEmpty)
    }

    @Test("A named provider without a credential is skipped, not silently dropped")
    func namedWithoutCredential() {
        let selection = Bench.resolveProviders([.one(.cohere), .one(.apple)]) { provider in
            provider == .apple ? .notNeeded : .notFound
        }
        #expect(selection.providers == [.apple])
        #expect(selection.skipped == [.cohere])
    }

    @Test("No provider with a credential leaves nothing to run")
    func nothingToRun() {
        let selection = Bench.resolveProviders([.one(.cohere), .one(.grok)]) { _ in .notFound }
        #expect(selection.providers.isEmpty)
        #expect(selection.skipped == [.cohere, .grok])
        #expect(CLIError.noRunnableProviders(selection.skipped).exitCode == 3)
        #expect(
            CLIError.noRunnableProviders(selection.skipped)
                .localizedDescription.contains("cohere, grok")
        )
    }

    @Test("A provider named twice runs once, in the order it was first named")
    func deduplication() {
        let selection = Bench.resolveProviders([.one(.apple), .one(.voz), .one(.apple)]) { _ in .notNeeded }
        #expect(selection.providers == [.apple, .voz])
    }

    // MARK: Directory expansion

    private func makeTree() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("speechkit-bench-\(UUID().uuidString)", isDirectory: true)
        let subdirectory = directory.appendingPathComponent("more", isDirectory: true)
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        for name in ["b.wav", "a.m4a", "notes.txt", "clip.MP3", ".hidden.wav"] {
            try Data().write(to: directory.appendingPathComponent(name))
        }
        for name in ["deep.flac", "readme.md"] {
            try Data().write(to: subdirectory.appendingPathComponent(name))
        }
        return directory
    }

    @Test("A directory contributes its audio files, sorted, without the hidden ones")
    func directoryExpansion() throws {
        let directory = try makeTree()
        defer { try? FileManager.default.removeItem(at: directory) }

        let files = AudioFileFinder.expand([directory.path], recursive: false)
        #expect(files.map(\.lastPathComponent) == ["a.m4a", "b.wav", "clip.MP3"])
    }

    @Test("--recursive reaches the subdirectories")
    func recursiveExpansion() throws {
        let directory = try makeTree()
        defer { try? FileManager.default.removeItem(at: directory) }

        let files = AudioFileFinder.expand([directory.path], recursive: true)
        #expect(files.map(\.lastPathComponent) == ["a.m4a", "b.wav", "clip.MP3", "deep.flac"])
    }

    @Test("A file named outright is taken whatever it is called")
    func namedFiles() throws {
        let directory = try makeTree()
        defer { try? FileManager.default.removeItem(at: directory) }

        let notes = directory.appendingPathComponent("notes.txt").path
        let missing = directory.appendingPathComponent("gone.wav").path
        let files = AudioFileFinder.expand([notes, missing], recursive: false)
        #expect(files.map(\.lastPathComponent) == ["notes.txt", "gone.wav"])
    }

    @Test("A file listed twice is benchmarked once")
    func deduplicatedFiles() throws {
        let directory = try makeTree()
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("b.wav").path
        let files = AudioFileFinder.expand([file, directory.path], recursive: false)
        #expect(files.map(\.lastPathComponent) == ["b.wav", "a.m4a", "clip.MP3"])
    }

    // MARK: Counting

    @Test("est_tokens rounds up from four characters to the token")
    func estimatedTokens() {
        #expect(BenchRow.estimatedTokens(forCharacters: 0) == 0)
        #expect(BenchRow.estimatedTokens(forCharacters: 1) == 1)
        #expect(BenchRow.estimatedTokens(forCharacters: 4) == 1)
        #expect(BenchRow.estimatedTokens(forCharacters: 5) == 2)
        #expect(BenchRow.estimatedTokens(forCharacters: 44) == 11)
    }

    @Test("chars and words count the transcript the way the summary reports it")
    func counting() {
        let text = "The quick, brown fox jumps over the lazy dog."
        #expect(text.count == 45)
        #expect(WordErrorRate.words(in: text).count == 9)
        #expect(BenchRow.estimatedTokens(forCharacters: text.count) == 12)
    }

    // MARK: Rendering

    /// Two rows, one measured and one failed, with a comma and quotes in the error.
    static var sampleReport: BenchReport {
        let measured = BenchRow(
            file: "talk.wav",
            provider: "apple",
            model: nil,
            audioSeconds: 2,
            wallSeconds: 0.5,
            wallMinSeconds: 0.4,
            realtimeFactor: 4,
            chars: 12,
            words: 3,
            estimatedTokens: 3,
            bytes: 13,
            segments: 1,
            hasWordTimings: true,
            wer: 0.25
        )
        let failed = BenchRow(
            file: "talk.wav",
            provider: "openai",
            status: "talk.wav is larger than the provider limit, and the \"limit\" is 25 MB, so nothing was uploaded."
        )
        return BenchReport(
            rows: [failed, measured],
            providers: [
                BenchProviderSummary.make(rows: [measured], provider: "apple"),
                BenchProviderSummary.make(rows: [failed], provider: "openai", setupSeconds: 1.5),
            ]
        )
    }

    @Test("The CSV quotes a status carrying a comma and doubles its quotes")
    func csv() {
        let lines = Self.sampleReport.csv().split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines[0] == "file,provider,model,audio_seconds,wall_seconds,wall_min_seconds,realtime_factor,processing_seconds,billed_seconds,total_tokens,chars,words,est_tokens,bytes,segments,has_word_timings,wer,status")
        #expect(lines[1] == "talk.wav,apple,,2.00,0.500,0.400,4.00,,,,12,3,3,13,1,yes,0.250,ok")
        #expect(lines[2] == "talk.wav,openai,,,,,,,,,,,,,,,,\"talk.wav is larger than the provider limit, and the \"\"limit\"\"\u{2026}\"")
        #expect(lines[3] == "")
        // Eighteen columns means seventeen separators on every line.
        for line in lines.dropLast() {
            #expect(line.filter { $0 == "," }.count >= 17)
        }
    }

    @Test("Rows are sorted by file and then provider")
    func sorting() {
        let report = BenchReport(
            rows: [
                BenchRow(file: "b.wav", provider: "apple"),
                BenchRow(file: "a.wav", provider: "voz"),
                BenchRow(file: "a.wav", provider: "apple"),
            ],
            providers: []
        )
        #expect(report.rows.map { "\($0.file)/\($0.provider)" } == ["a.wav/apple", "a.wav/voz", "b.wav/apple"])
    }

    @Test("A Markdown table pads its cells and escapes a pipe")
    func markdownTable() {
        let text = BenchReport.markdownTable(
            headers: ["file", "provider", "status"],
            rows: [
                ["talk.wav", "apple", "ok"],
                ["a.wav", "voz", "broke | badly"],
            ]
        )
        #expect(text == """
        | file     | provider | status         |
        | -------- | -------- | -------------- |
        | talk.wav | apple    | ok             |
        | a.wav    | voz      | broke \\| badly |

        """)
    }

    @Test("The Markdown summary carries both tables")
    func markdown() {
        let text = Self.sampleReport.markdown()
        #expect(text.hasPrefix("# Benchmark\n\n| file "))
        #expect(text.contains("\n## Providers\n\n"))
        #expect(text.contains("| provider | files | failures |"))
        #expect(text.contains("| apple    | 1     | 0        |"))
        #expect(text.contains("| openai   | 1     | 1        |"))
        // The setup cost of a provider pass is reported once, not per file.
        #expect(text.contains("1.50"))
    }

    @Test("The JSON summary keeps the whole error message")
    func json() throws {
        let text = try Self.sampleReport.json()
        #expect(text.contains("so nothing was uploaded."))
        #expect(!text.contains("\u{2026}"))

        let decoded = try JSONDecoder().decode(BenchReport.self, from: Data(text.utf8))
        #expect(decoded == Self.sampleReport)
        #expect(decoded.rows[0].status == BenchRow.okStatus)
    }

    @Test("The provider table printed to stdout aggregates the pass")
    func providerTable() {
        let text = Self.sampleReport.providerTable()
        #expect(text.hasPrefix("PROVIDER  FILES  FAILURES"))
        #expect(text.contains("apple     1      0"))
    }

    @Test("A provider aggregate divides total audio by total wall time")
    func aggregate() {
        let summary = BenchProviderSummary.make(
            rows: [
                BenchRow(file: "a.wav", provider: "apple", audioSeconds: 10, wallSeconds: 2, wer: 0.2),
                BenchRow(file: "b.wav", provider: "apple", audioSeconds: 30, wallSeconds: 3, wer: 0.4),
                BenchRow(file: "c.wav", provider: "apple", status: "broke"),
            ],
            provider: "apple"
        )
        #expect(summary.files == 3)
        #expect(summary.failures == 1)
        #expect(summary.audioSeconds == 40)
        #expect(summary.wallSeconds == 5)
        #expect(summary.realtimeFactor == 8)
        #expect(summary.meanWER == 0.30000000000000004)
    }

    // MARK: Metrics

    @Test("A document with no metrics encodes exactly the JSON it always did")
    func metricsOmitted() throws {
        let document = TranscriptDocument(provider: "apple", sourceFile: "/tmp/a.wav", text: "hi")
        #expect(document.metrics == nil)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let text = String(decoding: try encoder.encode(document), as: UTF8.self)
        #expect(!text.contains("metrics"))
    }

    @Test("A metrics record encodes only the fields the provider reported")
    func metricsEncoded() throws {
        let document = TranscriptDocument(
            provider: "voz",
            sourceFile: "/tmp/a.wav",
            text: "hi",
            metrics: TranscriptDocument.Metrics(processingSeconds: 0.25)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let text = String(decoding: try encoder.encode(document), as: UTF8.self)
        #expect(text.contains("\"metrics\":{\"processingSeconds\":0.25}"))

        let decoded = try JSONDecoder().decode(TranscriptDocument.self, from: Data(text.utf8))
        #expect(decoded.metrics?.processingSeconds == 0.25)
        #expect(decoded.metrics?.billedSeconds == nil)
    }

    @Test("An all-nil metrics record is dropped rather than attached")
    func emptyMetrics() {
        #expect(TranscriptDocument.Metrics().isEmpty)
        #expect(TranscriptDocument.Metrics().nonEmpty == nil)
        #expect(TranscriptDocument.Metrics(totalTokens: 4).nonEmpty != nil)
    }
}
