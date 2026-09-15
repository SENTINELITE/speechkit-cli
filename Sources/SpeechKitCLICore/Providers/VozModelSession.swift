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

    /// The approximate first-run download in megabytes.
    ///
    /// SpeechKit-Voz reports download progress as a fraction and publishes no
    /// byte count, so the megabytes beside the bar are this pinned total scaled
    /// by that fraction. It is the same number ``downloadSize`` names.
    nonisolated static let downloadMegabytes = 467

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
                await reporter.report(state)
            }
        }

        do {
            if loads {
                try await transcriber.waitUntilReady()
            } else {
                try await transcriber.downloadIfNeeded()
            }
        } catch {
            states.cancel()
            await reporter.finish()
            throw CLIError.modelNotReady(provider: .voz, reason: Self.message(for: error))
        }
        states.cancel()
        await reporter.finish()
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

/// Reports VOZ model preparation.
///
/// On a terminal the whole preparation is one live row: it names the phase,
/// counts the elapsed seconds, and draws a bar for the download. Through a
/// pipe the same run prints the handful of plain lines it always printed, one
/// every ten percent, so a log stays readable and unchanged.
@MainActor
final class VozProgressReporter {
    private let console: Console
    private let reportsDownload: Bool
    private let task: ProgressTask?
    private var lastPrintedStep = -1

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
        self.reportsDownload = reportsDownload
        // The console decides whether there is a live area to draw in. When
        // there is not, the handle prints nothing and the plain lines below
        // carry the run, exactly as they did before there was a renderer.
        let handle = console.task("voz: checking cached model files")
        self.task = handle.isLive ? handle : nil
    }

    /// Reports one model state.
    func report(_ state: VozModelState) async {
        guard console.verbosity != .quiet else { return }
        if let task {
            await report(state, on: task)
            return
        }
        switch state {
        case .unprepared:
            return
        case .checkingCache:
            guard console.verbosity == .verbose else { return }
            write("checking cached model files", step: -2)
        case .downloading(let progress):
            guard reportsDownload else { return }
            let percent = Int((min(max(progress, 0), 1) * 100).rounded())
            write("downloading \(percent)%", step: percent / 10)
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

    /// Closes the live row.
    ///
    /// Nothing is printed in its place: preparation is a phase of the run, and
    /// the lines that matter are the per-file ones that follow it. The plain
    /// path has already written whole lines and needs no closing.
    func finish() async {
        await task?.finish()
    }

    private func report(_ state: VozModelState, on task: ProgressTask) async {
        switch state {
        case .unprepared:
            return
        case .checkingCache:
            await task.update(label: "voz: checking cached model files")
        case .downloading(let progress):
            guard reportsDownload else { return }
            let fraction = min(max(progress, 0), 1)
            let total = VozModelSession.downloadMegabytes
            let done = Int((fraction * Double(total)).rounded())
            await task.update(label: "voz: downloading \(done) MB of \(total) MB")
            await task.update(fraction: fraction)
        case .loading:
            await task.update(fraction: nil)
            await task.update(
                label: "voz: loading model (first load specialises for the Neural Engine)"
            )
        case .ready:
            await task.update(label: "voz: ready")
        case .failed:
            return
        }
    }

    /// Prints one plain line, at most once per step.
    ///
    /// Only reached when there is no live area, so the line is whole and the
    /// download reports one line every ten percent rather than every frame.
    private func write(_ message: String, step: Int) {
        guard step != lastPrintedStep else { return }
        lastPrintedStep = step
        Console.writeStandardError("speechkit: voz: " + message + "\n")
    }
}
