import ArgumentParser
import Foundation
import SpeechKit

/// Transcribes one or more audio files.
public struct Transcribe: AsyncParsableCommand {
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

    /// How subtitle cues are split.
    @Option(name: .long, help: "Cue source for subtitles: segments or words.")
    public var cues: CueMode = .segments

    /// The longest subtitle cue, in seconds.
    @Option(name: .long, help: "Longest subtitle cue, in seconds.")
    public var maxCueDuration: Double = 7

    /// The longest subtitle cue, in characters.
    @Option(name: .long, help: "Longest subtitle cue, in characters.")
    public var maxCueChars: Int = 84

    /// How many files are transcribed at once.
    @Option(name: [.customShort("j"), .long], help: "Concurrent uploads, capped at 8.")
    public var jobs: Int = 2

    /// Includes the provider's raw response in JSON output.
    @Flag(name: .long, help: "Include the provider's raw response in JSON output.")
    public var raw: Bool = false

    /// Global verbosity flags.
    @OptionGroup public var globals: GlobalOptions

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
        if outputOptions.output != nil, outputOptions.stdout {
            throw ValidationError("--output and --stdout cannot be combined.")
        }
        if outputOptions.output != nil, files.count > 1 || formats.count > 1 {
            throw ValidationError("--output takes one input file and one format.")
        }
        if outputOptions.stdout, files.count > 1 || formats.count > 1 {
            throw ValidationError("--stdout takes one input file and one format.")
        }
        if let endpoint = transcription.endpoint, URL(string: endpoint) == nil {
            throw ValidationError("--endpoint is not a valid URL.")
        }
        if let timeout = transcription.timeout, timeout <= 0 {
            throw ValidationError("--timeout must be greater than zero.")
        }
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
        let resolver = CredentialResolver()
        guard let provider = provider ?? resolver.environmentProvider() else {
            throw CLIError.missingProvider
        }

        let capabilities = ProviderCapabilities.capabilities(for: provider)
        if transcription.words, !capabilities.supportsWordTimestamps {
            throw CLIError.unsupportedCapability(provider: provider, capability: "word timestamps")
        }
        if transcription.diarize, !capabilities.supportsDiarization {
            throw CLIError.unsupportedCapability(provider: provider, capability: "speaker labels")
        }
        if capabilities.requiresMacOS26, #unavailable(macOS 26.0) {
            throw CLIError.appleUnavailable
        }
        if jobs > 8 {
            console.warning("--jobs is capped at 8.")
        }

        let credential = try resolver.resolve(provider: provider, flagAPIKey: transcription.apiKey)
        let inputs = try resolvedInputs(capabilities: capabilities)
        let context = RunContext(
            credential: credential,
            model: transcription.model,
            languages: transcription.language,
            endpoint: transcription.endpoint.flatMap(URL.init(string:)),
            timeout: transcription.timeout,
            prompt: transcription.prompt,
            keywords: transcription.keyword,
            wantsWords: transcription.words,
            wantsDiarization: transcription.diarize,
            includeRaw: raw,
            maxCueDuration: maxCueDuration,
            maxCueChars: maxCueChars,
            cueMode: cues
        )
        let runner = try ProviderRegistry.makeRunner(for: provider, context: context)
        let writer = OutputWriter(
            outputDirectory: outputOptions.outputDir.map { URL(fileURLWithPath: $0, isDirectory: true) },
            explicitOutput: outputOptions.output.map { URL(fileURLWithPath: $0) },
            writesToStandardOutput: outputOptions.stdout,
            overwrite: outputOptions.overwrite,
            console: console
        )

        // Phase 3 replaces this loop with BatchRunner and --jobs concurrency.
        var failures = 0
        for (index, input) in inputs.enumerated() {
            let outcome = await run(
                file: input,
                index: index + 1,
                total: inputs.count,
                provider: provider,
                runner: runner,
                writer: writer,
                console: console
            )
            if let failure = outcome.failure {
                failures += 1
                console.error(failure.localizedDescription)
            }
        }

        if failures > 0 {
            throw ExitCode(2)
        }
    }

    /// Transcribes one file and writes every requested format.
    ///
    /// Phase 3 calls this from a task group, so it never throws.
    func run(
        file input: URL,
        index: Int,
        total: Int,
        provider: CLIProvider,
        runner: any ProviderRunner,
        writer: OutputWriter,
        console: Console
    ) async -> FileOutcome {
        let started = Date()
        do {
            let transcribed = try await runner.transcribe(file: input)
            let document = try cueAdjusted(transcribed)
            for warning in document.warnings {
                console.verbose("speechkit: note: \(warning)")
            }

            var destinations: [OutputWriter.Destination] = []
            for format in outputOptions.resolvedFormats {
                let formatter = try FormatterRegistry.makeFormatter(
                    for: format,
                    includesSpeakerLabels: transcription.diarize,
                    includesWordTimings: transcription.words,
                    cueBuilder: cueBuilder
                )
                let text = try formatter.render(document)
                destinations.append(
                    try writer.write(text, for: input, fileExtension: formatter.fileExtension)
                )
            }

            let elapsed = String(format: "%.1f s", Date().timeIntervalSince(started))
            let written = destinations.compactMap { destination -> String? in
                if case .file(let url) = destination { return url.lastPathComponent }
                return nil
            }
            let target = written.isEmpty ? "stdout" : written.joined(separator: ", ")
            console.progress("[\(index)/\(total)] \(input.lastPathComponent) -> \(target) (\(provider.rawValue), \(elapsed))")
            return FileOutcome(input: input, destinations: destinations, failure: nil)
        } catch let error as CLIError {
            return FileOutcome(input: input, destinations: [], failure: error)
        } catch {
            return FileOutcome(
                input: input,
                destinations: [],
                failure: .transcriptionFailed(file: input, reason: error.localizedDescription)
            )
        }
    }

    /// The cue builder carrying the `--max-cue-*` limits.
    var cueBuilder: CueBuilder {
        CueBuilder(maxCueDuration: maxCueDuration, maxCueChars: maxCueChars)
    }

    /// Returns the document with one cue per word when `--cues words` is set.
    ///
    /// - Throws: ``CLIError/usage(_:)`` when the provider returned no word
    ///   timings to build word cues from.
    func cueAdjusted(_ document: TranscriptDocument) throws -> TranscriptDocument {
        guard cues == .words, outputOptions.resolvedFormats.contains(where: \.requiresTimings) else {
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

    private func resolvedInputs(capabilities: ProviderCapabilities) throws -> [URL] {
        let manager = FileManager.default
        return try files.map { path in
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                throw CLIError.fileNotFound(url)
            }
            if isDirectory.boolValue {
                throw CLIError.inputIsDirectory(url)
            }
            if let limit = capabilities.maxFileBytes {
                let values = try? url.resourceValues(forKeys: [.fileSizeKey])
                if let size = values?.fileSize, Int64(size) > limit {
                    throw CLIError.fileTooLarge(url, limit: limit)
                }
            }
            return url
        }
    }
}
