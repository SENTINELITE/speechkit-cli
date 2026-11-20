import ArgumentParser
import Foundation

/// What `speechkit voz status` reports about the on-device model.
public struct VozStatusReport: Sendable, Codable, Equatable {
    /// The pinned model version.
    public let model: String
    /// Whether a complete verified model is already on disk.
    public let cached: Bool
    /// Where the model files live.
    public let cacheLocation: String
    /// The approximate first-run download.
    public let downloadSize: String

    /// Creates a report.
    public init(model: String, cached: Bool, cacheLocation: String, downloadSize: String) {
        self.model = model
        self.cached = cached
        self.cacheLocation = cacheLocation
        self.downloadSize = downloadSize
    }

    /// Builds the report for a cache answer.
    ///
    /// The in-memory model state is deliberately absent: a command-line process
    /// loads and drops the model within one run, so there is never a resident
    /// model for a later invocation to report.
    public static func make(cached: Bool) -> VozStatusReport {
        VozStatusReport(
            model: VozModelSession.modelVersion,
            cached: cached,
            cacheLocation: VozModelSession.managedCacheDescription,
            downloadSize: VozModelSession.downloadSize
        )
    }

    /// Renders the report as text.
    public func render() -> String {
        var text = "model: \(model)\n"
        text += "cached: \(cached ? "yes" : "no")\n"
        text += "cache: \(cacheLocation)\n"
        if !cached {
            text += "download: \(downloadSize). Run 'speechkit voz prepare' to fetch it.\n"
        }
        return text
    }
}

/// Manages the on-device VOZ model.
public struct Voz: AsyncParsableCommand {
    /// The command configuration.
    public static let configuration = CommandConfiguration(
        commandName: "voz",
        abstract: "Inspect and prepare the on-device VOZ model.",
        discussion: "Powered by Desert Ant Labs (https://desertant.com).",
        subcommands: [Status.self, Prepare.self],
        defaultSubcommand: Status.self
    )

    /// Creates the command.
    public init() {}

    /// Reports whether the model is downloaded.
    public struct Status: AsyncParsableCommand {
        /// The command configuration.
        public static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Report whether the VOZ model is downloaded."
        )

        /// Emits an object instead of text.
        @Flag(name: .long, help: "Emit JSON instead of text.")
        public var json: Bool = false

        /// Global verbosity flags.
        @OptionGroup public var globals: GlobalOptions

        /// Creates an empty command.
        public init() {}

        /// Runs the command.
        public func run() async throws {
            let session = VozModelSession()
            let report = VozStatusReport.make(cached: await session.isModelCached())
            let text: String
            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                text = String(decoding: try encoder.encode(report), as: UTF8.self) + "\n"
            } else {
                text = report.render()
            }
            FileHandle.standardOutput.write(Data(text.utf8))
        }
    }

    /// Downloads and loads the model once, so a later run starts transcribing immediately.
    public struct Prepare: AsyncParsableCommand {
        /// The command configuration.
        public static let configuration = CommandConfiguration(
            commandName: "prepare",
            abstract: "Download the VOZ model and load it once."
        )

        /// Fetches the files without loading the model.
        @Flag(name: .long, help: "Download the model files without loading them.")
        public var downloadOnly: Bool = false

        /// Global verbosity flags.
        @OptionGroup public var globals: GlobalOptions

        /// Creates an empty command.
        public init() {}

        /// Runs the command.
        public func run() async throws {
            let console = globals.console
            let session = VozModelSession()
            if downloadOnly {
                try await session.downloadOnly(console: console)
                console.note("The VOZ model files are downloaded.")
            } else {
                try await session.ensureReady(console: console, allowsDownload: true)
                await session.release()
                console.note("The VOZ model is downloaded and loads on this machine.")
            }
        }
    }
}
