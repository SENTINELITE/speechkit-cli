import Foundation
import SpeechKitVoz

/// Owns the one VOZ model a command uses, and reports its preparation.
///
/// `VozTranscriber` is main-actor isolated and holds a several-hundred-megabyte
/// Core ML model, so a run creates exactly one and shares it across every file
/// in the batch. The session is what the `transcribe` runner and the `voz`
/// subcommand both go through, so the download message, the progress lines, and
/// the error mapping are written once.
///
/// Preparation is cached in a single task: `--jobs 4` starts four files at once
/// and every one of them waits on the same download and load.
@MainActor
final class VozModelSession {
    /// The pinned model version, shown as the provider's default model.
    ///
    /// SpeechKit-Voz pins the `desert-ant-labs/voz` `v0.1.0` model and exposes
    /// no identifier for it, so the CLI names it here.
    nonisolated static let modelVersion = "voz v0.1.0"

    /// The approximate first-run download, as it appears in messages.
    nonisolated static let downloadSize = "about 467 MB"

    /// What `voz status` calls the cache when no directory was configured.
    ///
    /// SpeechKit-Voz resolves the location internally and publishes no
    /// accessor for it, so there is no path to print.
    nonisolated static let managedCacheDescription = "VOZ managed cache"

    private var storedTranscriber: VozTranscriber?
    private var preparation: Task<Void, Error>?

    /// Creates a session. No model file is touched until it is prepared.
    nonisolated init() {}

    /// The one transcriber this run uses, created on first use.
    ///
    /// `ProviderRunner.init(context:)` is not main-actor isolated and
    /// `VozTranscriber.init` is, so the transcriber cannot be built in the
    /// runner's initializer. Creating one touches neither disk nor network, so
    /// building it at the first main-actor hop costs nothing.
    var transcriber: VozTranscriber {
        if let storedTranscriber { return storedTranscriber }
        let created = VozTranscriber()
        storedTranscriber = created
        return created
    }

    /// Whether a complete verified model is already on disk.
    ///
    /// The check reads and digests every cached file, so it runs off the main
    /// actor to keep the progress lines moving.
    func isModelCached() async -> Bool {
        let transcriber = transcriber
        return await Task.detached { transcriber.isModelCached() }.value
    }

    /// Downloads and loads the model once, whatever the batch asks for it.
    ///
    /// - Parameters:
    ///   - console: The console progress and the download notice go to.
    ///   - allowsDownload: Whether a missing model may be fetched.
    /// - Throws: ``CLIError/modelDownloadRefused(provider:size:)`` when the
    ///   model is missing and `--no-download` was passed, or
    ///   ``CLIError/modelNotReady(provider:reason:)`` when it cannot be
    ///   prepared. Both exit with code 3, before any file is read.
    func ensureReady(console: Console, allowsDownload: Bool) async throws {
        if let preparation { return try await preparation.value }
        let task = Task { @MainActor in
            try await self.prepare(console: console, allowsDownload: allowsDownload, loads: true)
        }
        preparation = task
        return try await task.value
    }

    /// Fetches the model files without loading them, for `voz prepare --download-only`.
    func downloadOnly(console: Console) async throws {
        try await prepare(console: console, allowsDownload: true, loads: false)
    }

    /// Transcribes one file with the prepared model.
    ///
    /// `VozModelManager` chains every inference onto the previous one, so
    /// concurrent callers are already serialized and a `--jobs 4` batch cannot
    /// run four Core ML sessions at once.
    func transcribe(file: URL) async throws -> VozFileTranscriptionResponse {
        try await transcriber.transcribeAudioFile(file: file)
    }

    /// Drops the in-memory model, keeping its cached files.
    func release() {
        storedTranscriber?.release()
    }

    private func prepare(console: Console, allowsDownload: Bool, loads: Bool) async throws {
        let transcriber = transcriber
        let cached = await isModelCached()
        if !cached {
            guard allowsDownload else {
                throw CLIError.modelDownloadRefused(provider: .voz, size: Self.downloadSize)
            }
            console.note(
                "Downloading the VOZ model (\(Self.downloadSize)) to the \(Self.managedCacheDescription). Run 'speechkit voz prepare' ahead of time to do this once."
            )
        }

        let reporter = VozProgressReporter(console: console, reportsDownload: !cached)
        let states = Task { @MainActor in
            for await state in transcriber.stateUpdates {
                reporter.report(state)
            }
        }
        defer {
            states.cancel()
            reporter.finish()
        }

        do {
            if loads {
                try await transcriber.waitUntilReady()
            } else {
                try await transcriber.downloadIfNeeded()
            }
        } catch {
            throw CLIError.modelNotReady(provider: .voz, reason: Self.message(for: error))
        }
    }

    /// Returns the presentable text of a `VozError` or any other failure.
    nonisolated static func message(for error: Error) -> String {
        if let voz = error as? VozError, let description = voz.errorDescription {
            return description
        }
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

/// Prints VOZ model preparation to standard error.
///
/// On a terminal the line is rewritten in place, so a download does not scroll
/// a hundred percentages past. Through a pipe the same run prints a handful of
/// plain lines, one every ten percent, so a log stays readable.
@MainActor
final class VozProgressReporter {
    private let console: Console
    private let rewrites: Bool
    private let reportsDownload: Bool
    private var lastPrintedStep = -1
    private var wroteLine = false

    /// Creates a reporter for a console.
    ///
    /// - Parameters:
    ///   - console: Where the lines go.
    ///   - reportsDownload: Whether download progress is worth printing. A
    ///     cached model still walks through `downloading(progress: 1)` as VOZ
    ///     verifies the files it already has, and "downloading 100%" reads as a
    ///     fetch that never happened.
    init(console: Console, reportsDownload: Bool = true) {
        self.console = console
        self.rewrites = console.isStandardErrorTTY
        self.reportsDownload = reportsDownload
    }

    /// Prints one model state.
    func report(_ state: VozModelState) {
        guard console.verbosity != .quiet else { return }
        switch state {
        case .unprepared:
            return
        case .checkingCache:
            guard console.verbosity == .verbose else { return }
            write("checking cached model files", step: -2)
        case .downloading(let progress):
            guard reportsDownload else { return }
            let percent = Int((min(max(progress, 0), 1) * 100).rounded())
            write("downloading \(percent)%", step: rewrites ? percent : percent / 10)
        case .loading:
            write(
                "loading model (first load specialises for the Neural Engine and can take a few minutes)",
                step: 101
            )
        case .ready:
            write("ready", step: 102)
        case .failed:
            // The thrown error carries the message, so it is not printed twice.
            return
        }
    }

    /// Closes a rewritten line so later output starts on its own row.
    func finish() {
        guard wroteLine, rewrites else { return }
        Console.writeStandardError("\n")
        wroteLine = false
    }

    private func write(_ message: String, step: Int) {
        guard step != lastPrintedStep else { return }
        lastPrintedStep = step
        wroteLine = true
        if rewrites {
            // `\r` returns to the start of the line and `ESC[K` clears what the
            // previous, longer message left behind.
            Console.writeStandardError("\r\u{1B}[Kspeechkit: voz: " + message)
        } else {
            Console.writeStandardError("speechkit: voz: " + message + "\n")
        }
    }
}
