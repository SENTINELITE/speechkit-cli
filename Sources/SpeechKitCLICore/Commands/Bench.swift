import ArgumentParser
import Foundation

/// A `-p` value for `bench`, which accepts `all` as well as a provider name.
public enum BenchProviderSelection: Sendable, Equatable, ExpressibleByArgument {
    /// Every provider that could run on this machine right now.
    case all
    /// One named provider.
    case one(CLIProvider)

    /// Creates a selection from a case-insensitive argument.
    public init?(argument: String) {
        let value = argument.lowercased()
        if value == "all" {
            self = .all
            return
        }
        guard let provider = CLIProvider(argument: value) else { return nil }
        self = .one(provider)
    }

    /// The values `-p` accepts.
    public static var allValueStrings: [String] {
        CLIProvider.allValueStrings + ["all"]
    }
}

/// Compares providers over the same audio on speed, size, and accuracy.
///
/// The command is a measuring instrument, so the flag set is small on purpose:
/// anything that changes what a provider is asked for — an endpoint, a timeout,
/// a prompt, a per-provider model — would make two columns incomparable.
/// Credentials come from the environment and the keychain only, because a
/// `--api-key` can only belong to one of the providers being compared.
public struct Bench: AsyncParsableCommand, Sendable {
    /// The command configuration.
    public static let configuration = CommandConfiguration(
        commandName: "bench",
        abstract: "Compare providers over the same audio on speed, size, and accuracy."
    )

    /// The audio files and folders to benchmark.
    @Argument(help: "Audio files, or directories whose audio files are benchmarked.")
    public var inputs: [String] = []

    /// The providers to compare.
    @Option(
        name: [.customShort("p"), .long],
        help: "Provider: \(BenchProviderSelection.allValueStrings.joined(separator: ", ")). Repeatable. 'all' means every provider with a credential."
    )
    public var provider: [BenchProviderSelection] = []

    /// Language hints passed to every provider.
    @Option(name: [.customShort("l"), .long], help: "Language code such as en or en-US. Repeatable.")
    public var language: [String] = []

    /// Requests word-level timestamps from every provider.
    @Flag(name: .long, help: "Request word-level timestamps.")
    public var words: Bool = false

    /// Requests speaker labels from every provider.
    @Flag(name: .long, help: "Request speaker labels.")
    public var diarize: Bool = false

    /// The transcript formats written per file and provider.
    @Option(name: [.customShort("f"), .long], help: "Transcript format to write per file: txt, json, srt, or vtt. Repeatable.")
    public var format: [OutputFormat] = []

    /// Writes the full ``TranscriptDocument`` beside every transcript.
    @Flag(name: .long, help: "Also write the JSON document for every file, whatever --format says.")
    public var jsonTranscripts: Bool = false

    /// Where the reference transcripts live.
    @Option(name: .long, help: "Directory of <stem>.txt reference transcripts, for word error rate.")
    public var referenceDir: String?

    /// Walks subdirectories of an input directory.
    @Flag(name: .long, help: "Include audio files in subdirectories.")
    public var recursive: Bool = false

    /// Refuses to fetch an on-device model that is not cached yet.
    @Flag(name: .long, help: "Fail instead of downloading a missing on-device model.")
    public var noDownload: Bool = false

    /// Replaces existing transcript files.
    @Flag(name: .long, help: "Replace existing transcript files. Summary files are always rewritten.")
    public var overwrite: Bool = false

    /// How many files of one provider run at once.
    @Option(name: [.customShort("j"), .long], help: "Files in flight per provider, capped at 8. One by default, for fair timing.")
    public var jobs: Int = 1

    /// How many times each file is transcribed per provider.
    @Option(name: .customLong("repeat"), help: "Transcribe each file this many times and report the mean and the fastest.")
    public var repeatCount: Int = 1

    /// The directory the transcripts and the summaries are written to.
    @Option(name: [.customShort("o"), .long], help: "Directory for the transcripts and the summary files.")
    public var output: String

    /// Global verbosity flags.
    @OptionGroup public var globals: GlobalOptions

    /// The usage history opt-out.
    @OptionGroup public var history: HistoryOptions

    /// Creates an empty command.
    public init() {}

    /// Checks the flags that do not depend on a provider.
    public func validate() throws {
        guard !inputs.isEmpty else {
            throw ValidationError("Pass at least one audio file or directory.")
        }
        guard !provider.isEmpty else {
            throw ValidationError("Pass at least one --provider, or --provider all.")
        }
        if globals.quiet, globals.verbose {
            throw ValidationError("--quiet and --verbose cannot be combined.")
        }
        if jobs < 1 {
            throw ValidationError("--jobs must be at least 1.")
        }
        if repeatCount < 1 {
            throw ValidationError("--repeat must be at least 1.")
        }
    }

    /// The transcript formats written per file, with `--json-transcripts` folded in.
    public var resolvedFormats: [OutputFormat] {
        var formats = format.isEmpty ? [OutputFormat.txt] : format
        if jsonTranscripts, !formats.contains(.json) {
            formats.append(.json)
        }
        return formats
    }

    /// Runs the benchmark.
    public func run() async throws {
        let console = globals.console
        let files = AudioFileFinder.expand(inputs, recursive: recursive)
        guard !files.isEmpty else {
            throw CLIError.usage("No audio files found. Pass files, or a directory holding some.")
        }

        let referenceDirectory = referenceDir.map { URL(fileURLWithPath: $0, isDirectory: true) }

        let environment = ProcessInfo.processInfo.environment
        let store = KeychainStore()
        let selection = Self.resolveProviders(provider) { candidate in
            ProviderReport(provider: candidate, environment: environment, store: store).credentialSource
        }
        for skipped in selection.skipped {
            console.warning(
                "no credential for \(skipped.rawValue); skipping it. Set \(CredentialResolver.environmentVariableNames(for: skipped).joined(separator: " or ")) or run 'speechkit keys set \(skipped.rawValue)'."
            )
        }
        guard !selection.providers.isEmpty else {
            throw CLIError.noRunnableProviders(selection.skipped)
        }

        // The output directory is created after the providers are settled, so a
        // run with nothing to measure leaves no empty folder behind.
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        try Self.createDirectory(directory)

        var rows: [BenchRow] = []
        var summaries: [BenchProviderSummary] = []
        let resolver = CredentialResolver(environment: environment, keychain: store)
        let recorder = HistoryRecorder(noHistory: history.noHistory, console: console)

        for current in selection.providers {
            let (providerRows, setupSeconds) = await runPass(
                provider: current,
                files: files,
                referenceDirectory: referenceDirectory,
                directory: directory,
                resolver: resolver,
                console: console,
                recorder: recorder
            )
            rows += providerRows
            summaries.append(
                BenchProviderSummary.make(
                    rows: providerRows,
                    provider: current.rawValue,
                    setupSeconds: setupSeconds
                )
            )
        }

        let report = BenchReport(rows: rows, providers: summaries)
        try Self.write(report.csv(), to: directory.appendingPathComponent("summary.csv"))
        try Self.write(report.markdown(), to: directory.appendingPathComponent("summary.md"))
        try Self.write(report.json(), to: directory.appendingPathComponent("summary.json"))

        if globals.verbosity != .quiet {
            console.writeStandardOutput(report.providerTable())
        }
        for row in report.rows where !row.succeeded {
            console.error("\(row.provider): \(row.file): \(row.status)")
        }
        if report.rows.contains(where: { !$0.succeeded }) {
            throw ExitCode(2)
        }
    }

    /// Runs every file through one provider and returns its rows.
    ///
    /// The runner is built once for the whole pass, so VOZ downloads, loads, and
    /// specialises its model a single time however many files follow. That
    /// preparation is timed separately and reported as `setup_seconds`, because
    /// charging it to the first file would make the first row meaningless.
    ///
    /// - Returns: The rows, in input order, and what preparation cost.
    func runPass(
        provider current: CLIProvider,
        files: [URL],
        referenceDirectory: URL?,
        directory: URL,
        resolver: CredentialResolver,
        console: Console,
        recorder: HistoryRecorder = HistoryRecorder(store: nil)
    ) async -> (rows: [BenchRow], setupSeconds: Double?) {
        let capabilities = ProviderCapabilities.capabilities(for: current)
        let clock = ContinuousClock()
        let setupStarted = clock.now

        let runner: any ProviderRunner
        do {
            let context = RunContext(
                credential: try resolver.resolve(provider: current),
                languages: language,
                wantsWords: Transcribe.wantsWords(
                    requested: words,
                    formats: resolvedFormats,
                    provider: current
                ),
                wantsDiarization: diarize,
                allowsModelDownload: !noDownload,
                console: console
            )
            runner = try await ProviderRegistry.makeRunner(for: current, context: context)
        } catch {
            // A provider that cannot be set up at all — a model it rejects, an
            // operating system it needs, a model it will not download — fails
            // its own files and leaves the other providers' rows alone.
            let reason = Self.message(for: error)
            console.warning("\(current.rawValue): \(reason)")
            let rows = files.map { file in
                BenchRow(file: file.lastPathComponent, provider: current.rawValue, status: reason)
            }
            // Every file the provider never got to is still a recorded run, so
            // a provider that cannot start is visible in the failure column.
            for file in files {
                await recorder.record(
                    historyRecord(
                        file: file,
                        provider: current,
                        wallSeconds: 0,
                        status: HistoryRecord.status(for: error),
                        errorMessage: HistoryRecord.errorMessage(reason)
                    )
                )
            }
            return (rows, nil)
        }
        let setupSeconds = (clock.now - setupStarted).benchSeconds

        let rows = await BatchRunner(jobs: jobs, console: console).run(inputs: files) { file, index, total in
            await measure(
                file: file,
                index: index,
                total: total,
                provider: current,
                capabilities: capabilities,
                runner: runner,
                referenceDirectory: referenceDirectory,
                directory: directory,
                console: console,
                recorder: recorder
            )
        }
        await runner.finish()
        return (rows, setupSeconds)
    }

    /// Transcribes one file with one provider and measures it.
    ///
    /// Only the provider call is timed. Validation, formatting, writing, and
    /// the word error rate all happen outside the clock, so `wall_seconds` is
    /// the provider's number and nothing else.
    func measure(
        file: URL,
        index: Int,
        total: Int,
        provider current: CLIProvider,
        capabilities: ProviderCapabilities,
        runner: any ProviderRunner,
        referenceDirectory: URL?,
        directory: URL,
        console: Console,
        recorder: HistoryRecorder = HistoryRecorder(store: nil)
    ) async -> BenchRow {
        let measureStarted = Date()
        let position = "[\(current.rawValue) \(index)/\(total)] \(file.lastPathComponent)"
        let task = console.task("\(position) transcribing")
        func failed(_ error: Error) async -> BenchRow {
            // A failed file is a row in the table with a reason in it, not a
            // line of its own, so the row simply leaves the live area.
            await task.fail()
            let reason = Self.message(for: error)
            await recorder.record(
                historyRecord(
                    file: file,
                    provider: current,
                    wallSeconds: Date().timeIntervalSince(measureStarted),
                    status: HistoryRecord.status(for: error),
                    errorMessage: HistoryRecord.errorMessage(reason)
                )
            )
            return BenchRow(file: file.lastPathComponent, provider: current.rawValue, status: reason)
        }

        do {
            try InputValidation.check(file, capabilities: capabilities)
        } catch {
            return await failed(error)
        }

        let clock = ContinuousClock()
        var samples: [Double] = []
        var transcript: TranscriptDocument?
        for pass in 0..<repeatCount {
            if repeatCount > 1 {
                await task.update(label: "\(position) transcribing \(pass + 1) of \(repeatCount)")
            }
            let started = clock.now
            do {
                let document = try await runner.transcribe(file: file)
                samples.append((clock.now - started).benchSeconds)
                transcript = document
            } catch {
                return await failed(error)
            }
        }
        guard let document = transcript, let meanWall = samples.mean else {
            return await failed(CLIError.transcriptionFailed(file: file, reason: "the provider returned nothing."))
        }

        await task.update(label: "\(position) writing")

        let plain: String
        do {
            plain = try PlainTextFormatter(includesSpeakerLabels: diarize).render(document)
            for format in resolvedFormats {
                let formatter = try FormatterRegistry.makeFormatter(
                    for: format,
                    includesSpeakerLabels: diarize,
                    includesWordTimings: words
                )
                try write(
                    formatter.render(document),
                    file: file,
                    provider: current,
                    fileExtension: formatter.fileExtension,
                    directory: directory,
                    console: console
                )
            }
        } catch {
            return await failed(error)
        }

        var audioSeconds = document.duration
        if audioSeconds == nil {
            // Aqua, Cohere, and ElevenLabs report no duration, and a realtime
            // factor needs one, so the file is probed rather than left blank.
            audioSeconds = await AudioDuration.seconds(of: file)
        }
        let characters = document.text.count
        let reference = WordErrorRate.referenceText(for: file, directory: referenceDirectory)
        var realtimeFactor: Double?
        if let audioSeconds, meanWall > 0 {
            realtimeFactor = audioSeconds / meanWall
        }
        let row = BenchRow(
            file: file.lastPathComponent,
            provider: current.rawValue,
            model: document.model,
            audioSeconds: audioSeconds,
            wallSeconds: meanWall,
            wallMinSeconds: samples.min(),
            realtimeFactor: realtimeFactor,
            processingSeconds: document.metrics?.processingSeconds,
            billedSeconds: document.metrics?.billedSeconds,
            totalTokens: document.metrics?.totalTokens,
            chars: characters,
            words: WordErrorRate.words(in: document.text).count,
            estimatedTokens: BenchRow.estimatedTokens(forCharacters: characters),
            bytes: plain.utf8.count,
            segments: document.segments.count,
            hasWordTimings: document.words.contains { $0.start != nil },
            wer: reference.flatMap { WordErrorRate.rate(reference: $0, hypothesis: document.text) }
        )

        await recorder.record(
            historyRecord(
                file: file,
                provider: current,
                model: document.model,
                audioSeconds: audioSeconds,
                wallSeconds: meanWall,
                wordCount: row.words ?? 0,
                charCount: characters,
                status: HistoryStatus.ok
            )
        )

        let factor = row.realtimeFactor.map { String(format: " (%.1fx)", $0) } ?? ""
        await task.finish(
            line: String(
                format: "[%@ %d/%d] %@ %.1f s%@",
                current.rawValue,
                index,
                total,
                file.lastPathComponent,
                meanWall,
                factor
            )
        )
        return row
    }

    /// Fills in the fields every `bench` record shares.
    ///
    /// One record per file per provider, carrying the `--repeat` count, so a
    /// three-repeat pass is not read later as three separate runs.
    func historyRecord(
        file: URL,
        provider current: CLIProvider,
        model: String? = nil,
        audioSeconds: Double? = nil,
        wallSeconds: Double,
        wordCount: Int = 0,
        charCount: Int = 0,
        status: String,
        errorMessage: String? = nil
    ) -> HistoryRecord {
        HistoryRecord(
            command: "bench",
            provider: current.rawValue,
            model: model,
            fileName: file.lastPathComponent,
            filePath: file.standardizedFileURL.path,
            inputBytes: Transcribe.fileSize(of: file),
            audioSeconds: audioSeconds,
            wallSeconds: wallSeconds,
            words: wordCount,
            chars: charCount,
            formats: resolvedFormats.map(\.rawValue),
            wantsWords: words,
            wantsDiarization: diarize,
            repeatCount: repeatCount,
            status: status,
            errorMessage: errorMessage
        )
    }

    /// Writes one transcript as `<stem>.<provider>.<extension>`.
    ///
    /// A transcript that is already there is left alone without `--overwrite`,
    /// the same as `transcribe` does, so a second provider added to an old
    /// benchmark does not silently rewrite the first one's output.
    func write(
        _ text: String,
        file: URL,
        provider current: CLIProvider,
        fileExtension: String,
        directory: URL,
        console: Console
    ) throws {
        let stem = file.deletingPathExtension().lastPathComponent
        let url = directory
            .appendingPathComponent("\(stem).\(current.rawValue)")
            .appendingPathExtension(fileExtension)
        if FileManager.default.fileExists(atPath: url.path), !overwrite {
            console.warning("\(url.path) exists; skipped. Pass --overwrite to replace it.")
            return
        }
        try Self.write(text, to: url)
    }

    /// Returns the providers that will run, and the ones skipped for want of a credential.
    ///
    /// `all` expands to every provider with a credential or with no need for
    /// one, which is exactly what `speechkit providers` shows in its credential
    /// column. A provider named explicitly but missing its key is a warning and
    /// a skip rather than the end of the run, because the other providers still
    /// have something to say about the same folder.
    ///
    /// - Parameters:
    ///   - selections: The `-p` values, in order.
    ///   - credentialSource: Where a provider's credential would come from.
    ///     Tests inject a fixed answer rather than reading the real keychain.
    public static func resolveProviders(
        _ selections: [BenchProviderSelection],
        credentialSource: (CLIProvider) -> CredentialSource
    ) -> (providers: [CLIProvider], skipped: [CLIProvider]) {
        var requested: [CLIProvider] = []
        for selection in selections {
            switch selection {
            case .all:
                requested += CLIProvider.allCases
            case .one(let provider):
                requested.append(provider)
            }
        }

        var seen: Set<CLIProvider> = []
        var providers: [CLIProvider] = []
        var skipped: [CLIProvider] = []
        let expandsAll = selections.contains(.all)
        for candidate in requested where seen.insert(candidate).inserted {
            if credentialSource(candidate) == .notFound {
                // `all` means "whatever can run here", so a provider without a
                // key is not worth a warning; a named one is.
                if !expandsAll { skipped.append(candidate) }
            } else {
                providers.append(candidate)
            }
        }
        return (providers, skipped)
    }

    /// Returns the presentable text of any failure.
    static func message(for error: Error) -> String {
        FailureMessage.message(for: error)
    }

    static func createDirectory(_ directory: URL) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw CLIError.writeFailed(directory, reason: error.localizedDescription)
        }
    }

    static func write(_ text: String, to url: URL) throws {
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            throw CLIError.writeFailed(url, reason: error.localizedDescription)
        }
    }
}

extension Duration {
    /// The duration in seconds, for a measurement taken with `ContinuousClock`.
    var benchSeconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}

extension [Double] {
    /// The arithmetic mean, or `nil` when there is nothing to average.
    var mean: Double? {
        isEmpty ? nil : reduce(0, +) / Double(count)
    }
}
