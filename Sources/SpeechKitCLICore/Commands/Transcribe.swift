import ArgumentParser
import Foundation
import SpeechKit

/// Transcribes one or more audio files.
public struct Transcribe: AsyncParsableCommand, Sendable {
    /// The command configuration.
    public static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Transcribe audio files and write text, JSON, or subtitles."
    )

    /// The audio files to transcribe.
    @Argument(help: "One or more audio files. Shell globs are expanded by the shell.")
    public var files: [String] = []

    /// The provider to transcribe with.
    @Option(name: [.customShort("p"), .long], help: "Provider: \(CLIProvider.allValueStrings.joined(separator: ", ")). Defaults to SPEECHKIT_PROVIDER.")
    public var provider: CLIProvider?

    /// Transcription behaviour flags.
    @OptionGroup public var transcription: TranscriptionOptions

    /// Output destination flags.
    @OptionGroup public var outputOptions: OutputOptions

    /// How segments and subtitle cues are split. `nil` picks the provider's default.
    @Option(name: .long, help: "Cue source: segments, sentences, or words. Defaults to sentences for VOZ and Fish Audio, and segments otherwise.")
    public var cues: CueMode?

    /// The longest subtitle cue, in seconds.
    @Option(name: .long, help: "Longest subtitle cue, in seconds.")
    public var maxCueDuration: Double = 7

    /// The longest subtitle cue, in characters.
    @Option(name: .long, help: "Longest subtitle cue, in characters.")
    public var maxCueChars: Int = 84

    /// How many files are transcribed at once.
    @Option(name: [.customShort("j"), .long], help: "Concurrent uploads, capped at 8.")
    public var jobs: Int = 2

    /// Global verbosity flags.
    @OptionGroup public var globals: GlobalOptions

    /// The usage history opt-out.
    @OptionGroup public var history: HistoryOptions

    /// Creates an empty command.
    public init() {}

    /// Checks flag combinations that do not depend on the provider.
    public func validate() throws {
        guard !files.isEmpty else {
            throw ValidationError("Pass at least one audio file.")
        }
        if globals.quiet, globals.verbose {
            throw ValidationError("--quiet and --verbose cannot be combined.")
        }

        let formats = outputOptions.resolvedFormats
        if maxCueDuration <= 0 {
            throw ValidationError("--max-cue-duration must be greater than zero.")
        }
        if maxCueChars <= 0 {
            throw ValidationError("--max-cue-chars must be greater than zero.")
        }
        if jobs < 1 {
            throw ValidationError("--jobs must be at least 1.")
        }
        let severalOutputs = files.count > 1 || formats.count > 1
        switch outputOptions.target {
        case .standardOutput where severalOutputs:
            throw ValidationError(
                "Without --output, one input file and one format go to stdout. Pass --output <directory> to write several files."
            )
        case .file where severalOutputs:
            throw ValidationError(
                "--output names a single file, which takes one input file and one format. Pass a directory (end it with /) to write several."
            )
        default:
            break
        }
        if let endpoint = transcription.endpoint { _ = try EndpointValidation.url(endpoint, option: "--endpoint") }
        if let endpoint = transcription.filesEndpoint { _ = try EndpointValidation.url(endpoint, option: "--files-endpoint") }
        if let timeout = transcription.timeout, timeout <= 0 {
            throw ValidationError("--timeout must be greater than zero.")
        }
        if let hint = Self.subcommandHint(for: files) {
            throw ValidationError(hint)
        }
    }

    /// Returns a hint when a positional argument reads like a mistyped subcommand.
    ///
    /// `transcribe` is the default subcommand, so `speechkit bogus` parses as a
    /// file to transcribe and would otherwise fail with "No provider", which
    /// says nothing about the real mistake. A bare word with no extension and no
    /// path separator that does not exist on disk is almost always a subcommand.
    static func subcommandHint(for files: [String]) -> String? {
        let manager = FileManager.default
        for file in files {
            guard !manager.fileExists(atPath: file) else { continue }
            guard !file.contains("/"), URL(fileURLWithPath: file).pathExtension.isEmpty else { continue }
            return "'\(file)' is not a file. If you meant a subcommand, run 'speechkit --help'."
        }
        return nil
    }

    /// The outcome of transcribing one file.
    public struct FileOutcome: Sendable {
        /// The input file.
        public let input: URL
        /// Where output went, when the file succeeded.
        public let destinations: [OutputWriter.Destination]
        /// The failure, when the file failed.
        public let failure: CLIError?
    }

    /// Runs the command.
    public func run() async throws {
        let console = globals.console
        let resolver = CredentialResolver(keychain: KeychainStore())
        guard let provider = provider ?? resolver.environmentProvider() else {
            throw CLIError.missingProvider
        }

        let capabilities = ProviderCapabilities.capabilities(for: provider)
        // Everything that can be known before a byte leaves the machine is
        // checked here, so a rejected run costs no upload and exits with 1.
        let inputs = try validate(provider: provider, capabilities: capabilities)

        let credential = try resolver.resolve(provider: provider, flagAPIKey: transcription.apiKey)
        let context = RunContext(
            credential: credential,
            model: transcription.model,
            languages: transcription.language,
            endpoint: transcription.endpoint.flatMap(URL.init(string:)),
            filesEndpoint: transcription.filesEndpoint.flatMap(URL.init(string:)),
            timeout: transcription.timeout,
            prompt: transcription.prompt,
            keywords: transcription.keyword,
            wantsWords: Self.wantsWords(
                requested: transcription.words,
                formats: outputOptions.resolvedFormats,
                provider: provider,
                cueMode: cueMode(for: provider)
            ),
            wantsDiarization: transcription.diarize,
            maxCueDuration: maxCueDuration,
            maxCueChars: maxCueChars,
            cueMode: cueMode(for: provider),
            allowsModelDownload: !transcription.noDownload,
            console: console
        )
        let runner = try await ProviderRegistry.makeRunner(for: provider, context: context)
        let writer = OutputWriter(
            target: outputOptions.target,
            overwrite: outputOptions.overwrite,
            console: console
        )

        let recorder = HistoryRecorder(noHistory: history.noHistory, console: console)
        let outcomes = await BatchRunner(jobs: jobs, console: console).run(inputs: inputs) { input, index, total in
            await run(
                file: input,
                index: index,
                total: total,
                provider: provider,
                runner: runner,
                writer: writer,
                console: console,
                recorder: recorder
            )
        }

        await runner.finish()

        // Outcomes come back in input order, so failures are reported in the
        // order the files were named however the uploads interleaved.
        let failures = outcomes.compactMap(\.failure)
        for failure in failures {
            console.error(failure.localizedDescription)
        }
        if !failures.isEmpty {
            throw ExitCode(2)
        }
    }

    /// Checks everything that can be known before the first upload.
    ///
    /// - Parameters:
    ///   - provider: The resolved provider.
    ///   - capabilities: Its capability record. Tests pass a record with a small
    ///     byte limit to exercise the size check.
    /// - Returns: The input files, in the order they were named.
    /// - Throws: ``CLIError`` with exit code 1 for any problem found here.
    func validate(provider: CLIProvider, capabilities: ProviderCapabilities) throws -> [URL] {
        if transcription.words, !capabilities.supportsWordTimestamps {
            throw CLIError.unsupportedCapability(provider: provider, capability: "word timestamps")
        }
        if cues == .sentences, !capabilities.supportsWordTimestamps {
            throw CLIError.unsupportedCapability(provider: provider, capability: "sentence cues")
        }
        if transcription.diarize, !capabilities.supportsDiarization {
            throw CLIError.unsupportedCapability(provider: provider, capability: "speaker labels")
        }
        if capabilities.requiresMacOS26, #unavailable(macOS 26.0) {
            throw CLIError.appleUnavailable
        }

        // Providers that return text only can never produce subtitles. Refusing
        // here rather than after the upload is the difference between exit 1
        // and a wasted round trip.
        let subtitleFormats = outputOptions.resolvedFormats.filter(\.requiresTimings)
        if !subtitleFormats.isEmpty, !capabilities.supportsSegments {
            throw CLIError.subtitlesUnsupported(
                provider: provider,
                formats: subtitleFormats.map(\.rawValue)
            )
        }

        let inputs = try resolvedInputs(capabilities: capabilities)
        try checkDestinationCollisions(inputs)
        return inputs
    }

    /// The providers whose segments are built from word timings.
    ///
    /// A subtitle format from one of these needs word timings, so `-f srt` has
    /// to ask for them even when `--words` was not passed. Meta returns turns
    /// and Apple returns entries, so neither needs the request. Fish Audio
    /// always asks for timestamps, because its speaker turns need them too.
    static let wordSegmentProviders: Set<CLIProvider> = [.grok, .gemini, .openai, .elevenlabs]

    /// Returns whether the run should ask the provider for word timings.
    ///
    /// - Parameters:
    ///   - requested: Whether `--words` was passed.
    ///   - formats: The requested output formats.
    ///   - provider: The resolved provider.
    ///   - cueMode: The resolved cue mode. Sentences are built from words, so
    ///     they need the request just as subtitles do.
    static func wantsWords(
        requested: Bool,
        formats: [OutputFormat],
        provider: CLIProvider,
        cueMode: CueMode = .segments
    ) -> Bool {
        if requested { return true }
        guard cueMode == .sentences || formats.contains(where: \.requiresTimings) else { return false }
        return wordSegmentProviders.contains(provider)
    }

    /// The providers whose cue mode defaults to sentences.
    ///
    /// VOZ returns words only, so its segments are built by the CLI either way,
    /// and sentences read better than pause-sized fragments. Fish Audio's
    /// speaker turns run long, but SpeechKit punctuates its words, so sentences
    /// split cleanly. The other cloud providers keep their segments, which some
    /// of them send themselves.
    static let sentenceCueProviders: Set<CLIProvider> = [.voz, .fishAudio]

    /// Returns the cue mode for a provider: `--cues` when passed, and otherwise
    /// sentences for VOZ and Fish Audio and segments for everyone else.
    func cueMode(for provider: CLIProvider?) -> CueMode {
        if let cues { return cues }
        guard let provider else { return .segments }
        return Self.sentenceCueProviders.contains(provider) ? .sentences : .segments
    }

    /// Rejects two inputs that would write over each other.
    ///
    /// Outputs in a directory are named after the input stem, so `talk.wav`
    /// and `talk.m4a` in one run both want `talk.txt`. Whichever finished last
    /// would win, so the run is refused before any upload.
    ///
    /// - Throws: ``CLIError/usage(_:)`` naming both inputs and the shared path.
    func checkDestinationCollisions(_ inputs: [URL]) throws {
        guard case .directory(let directory) = outputOptions.target else { return }

        var seen: [String: URL] = [:]
        for input in inputs {
            let stem = input.deletingPathExtension().lastPathComponent
            let key = directory.appendingPathComponent(stem).standardizedFileURL.path
            if let first = seen[key] {
                let format = outputOptions.resolvedFormats[0].rawValue
                throw CLIError.usage(
                    "\(first.path) and \(input.path) would both be written to \(key).\(format). Rename one, or transcribe them in separate runs."
                )
            }
            seen[key] = input
        }
    }

    /// Transcribes one file and writes every requested format.
    ///
    /// Phase 3 calls this from a task group, so it never throws. Both the
    /// success and the failure are recorded in the usage history, which never
    /// fails the run either.
    func run(
        file input: URL,
        index: Int,
        total: Int,
        provider: CLIProvider,
        runner: any ProviderRunner,
        writer: OutputWriter,
        console: Console,
        recorder: HistoryRecorder = HistoryRecorder(store: nil)
    ) async -> FileOutcome {
        let started = Date()
        // The live row carries the same `[2/5] talk.wav` prefix its closing
        // line will, so a file keeps one identity from first frame to
        // scrollback.
        let position = "[\(index)/\(total)] \(input.lastPathComponent)"
        let task = console.task("\(position) transcribing")
        do {
            let transcribed = try await runner.transcribe(file: input)
            let document = try cueAdjusted(transcribed, provider: provider)
            await task.update(label: "\(position) writing")
            // Notes belong at normal verbosity: "--language was ignored" is not
            // a detail the run can afford to hide behind --verbose.
            for warning in document.warnings {
                console.warning(total > 1 ? "\(input.lastPathComponent): \(warning)" : warning)
            }

            var destinations: [OutputWriter.Destination] = []
            for format in outputOptions.resolvedFormats {
                let formatter = try FormatterRegistry.makeFormatter(
                    for: format,
                    includesSpeakerLabels: transcription.diarize,
                    includesWordTimings: transcription.words,
                    includesTimestamps: !outputOptions.noTimestamps,
                    cueBuilder: cueBuilder
                )
                let text = try formatter.render(document)
                destinations.append(
                    try writer.write(text, for: input, fileExtension: formatter.fileExtension)
                )
            }

            let seconds = Date().timeIntervalSince(started)
            let elapsed = String(format: "%.1f s", seconds)
            let target = Self.progressTarget(for: destinations)
            await task.finish(
                line: "\(position) -> \(target) (\(provider.rawValue), \(elapsed))"
            )

            if recorder.isEnabled {
                var audioSeconds = document.duration
                if audioSeconds == nil { audioSeconds = await AudioDuration.seconds(of: input) }
                await recorder.record(
                    historyRecord(
                        file: input,
                        provider: provider,
                        model: document.model,
                        audioSeconds: audioSeconds,
                        wallSeconds: seconds,
                        words: WordErrorRate.words(in: document.text).count,
                        chars: document.text.count,
                        status: HistoryStatus.ok,
                        errorMessage: nil
                    )
                )
            }
            return FileOutcome(input: input, destinations: destinations, failure: nil)
        } catch let error as CLIError {
            // The row goes away without a line of its own: failures are
            // reported together in input order once the batch is done, which
            // is what a piped run has always printed.
            await task.fail()
            await record(error, file: input, provider: provider, started: started, recorder: recorder)
            return FileOutcome(input: input, destinations: [], failure: error)
        } catch {
            await task.fail()
            let failure = CLIError.transcriptionFailed(file: input, reason: FailureMessage.message(for: error))
            await record(failure, file: input, provider: provider, started: started, recorder: recorder)
            return FileOutcome(input: input, destinations: [], failure: failure)
        }
    }

    /// Records one failed file.
    private func record(
        _ error: CLIError,
        file input: URL,
        provider: CLIProvider,
        started: Date,
        recorder: HistoryRecorder
    ) async {
        guard recorder.isEnabled else { return }
        await recorder.record(
            historyRecord(
                file: input,
                provider: provider,
                model: transcription.model,
                audioSeconds: nil,
                wallSeconds: Date().timeIntervalSince(started),
                words: 0,
                chars: 0,
                status: HistoryRecord.status(for: error),
                errorMessage: HistoryRecord.errorMessage(error.localizedDescription)
            )
        )
    }

    /// Fills in the fields every `transcribe` record shares.
    private func historyRecord(
        file input: URL,
        provider: CLIProvider,
        model: String?,
        audioSeconds: Double?,
        wallSeconds: Double,
        words: Int,
        chars: Int,
        status: String,
        errorMessage: String?
    ) -> HistoryRecord {
        HistoryRecord(
            command: "transcribe",
            provider: provider.rawValue,
            model: model,
            fileName: input.lastPathComponent,
            filePath: input.standardizedFileURL.path,
            inputBytes: Self.fileSize(of: input),
            audioSeconds: audioSeconds,
            wallSeconds: wallSeconds,
            words: words,
            chars: chars,
            formats: outputOptions.resolvedFormats.map(\.rawValue),
            outputDirectory: Self.outputDirectory(of: outputOptions.target),
            wantsWords: transcription.words,
            wantsDiarization: transcription.diarize,
            status: status,
            errorMessage: errorMessage
        )
    }

    /// Returns the recorded `--output` directory, when the run wrote into one.
    ///
    /// Standard output and a single named file have no directory to remember,
    /// so neither is recorded and neither is offered as a default later.
    static func outputDirectory(of target: OutputTarget) -> String? {
        guard case .directory(let url) = target else { return nil }
        return url.standardizedFileURL.path
    }

    /// Returns the size of a file in bytes, or `nil` when it cannot be read.
    static func fileSize(of url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    }

    /// Returns what the progress line says a file was written to.
    ///
    /// A skipped file is spelled out rather than listed like a write, so the
    /// line never claims an output the run did not produce.
    ///
    /// - Parameter destinations: The destinations for one input file.
    static func progressTarget(for destinations: [OutputWriter.Destination]) -> String {
        let written = destinations.compactMap { destination -> String? in
            switch destination {
            case .file(let url):
                return url.lastPathComponent
            case .skipped(let url):
                return "\(url.lastPathComponent) (exists, skipped)"
            case .standardOutput:
                return nil
            }
        }
        return written.isEmpty ? "stdout" : written.joined(separator: ", ")
    }

    /// The cue builder carrying the `--max-cue-*` limits.
    var cueBuilder: CueBuilder {
        CueBuilder(maxCueDuration: maxCueDuration, maxCueChars: maxCueChars)
    }

    /// Returns the document with its segments rebuilt for the cue mode.
    ///
    /// `--cues sentences` replaces the segments with one per sentence, for every
    /// format, so JSON carries the same sentences the subtitles do. `--cues
    /// words` replaces them with one per word, and only when a subtitle format
    /// was asked for.
    ///
    /// - Parameters:
    ///   - document: The provider's transcript.
    ///   - provider: The resolved provider, which picks the default cue mode.
    ///     `nil` uses `--provider`.
    /// - Throws: ``CLIError/usage(_:)`` when `--cues words` or an explicit
    ///   `--cues sentences` meets a provider that returned no word timings.
    func cueAdjusted(_ document: TranscriptDocument, provider: CLIProvider? = nil) throws -> TranscriptDocument {
        let mode = cueMode(for: provider ?? self.provider)
        if mode == .sentences {
            guard document.words.contains(where: { $0.start != nil }) else {
                // The VOZ and Fish Audio default should never fail a run;
                // only an explicit request that cannot be met is an error.
                guard cues == .sentences else { return document }
                throw CLIError.usage(
                    "--cues sentences needs word timings, and \(document.provider) returned none. Pass --words, or use --cues segments."
                )
            }
            var document = document
            document.segments = RunnerSupport.orderedSegments(cueBuilder.sentences(from: document.words))
            return document
        }
        guard mode == .words, outputOptions.resolvedFormats.contains(where: \.requiresTimings) else {
            return document
        }
        guard !document.words.isEmpty else {
            throw CLIError.usage(
                "--cues words needs word timings, and \(document.provider) returned none. Pass --words, or use --cues segments."
            )
        }
        var document = document
        document.segments = cueBuilder.wordCues(from: document.words)
        return document
    }

    /// Returns the input files, checked against the provider's limits.
    ///
    /// The per-file checks live in ``InputValidation`` so `bench` can apply the
    /// same ones per provider without raising them as usage errors.
    func resolvedInputs(capabilities: ProviderCapabilities) throws -> [URL] {
        try files.map { path in
            let url = URL(fileURLWithPath: path)
            try InputValidation.check(url, capabilities: capabilities)
            return url
        }
    }
}
