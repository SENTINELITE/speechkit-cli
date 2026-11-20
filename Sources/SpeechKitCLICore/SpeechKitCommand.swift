import ArgumentParser
import Foundation

/// Options shared by every `speechkit` subcommand.
public struct GlobalOptions: ParsableArguments, Sendable {
    /// Prints per-file progress and timing to standard error.
    @Flag(name: [.customShort("v"), .long], help: "Print progress and timing to stderr.")
    public var verbose: Bool = false

    /// Suppresses warnings and progress on standard error.
    @Flag(name: [.customShort("q"), .long], help: "Suppress warnings and progress.")
    public var quiet: Bool = false

    /// Creates empty global options.
    public init() {}

    /// The console verbosity implied by the flags.
    public var verbosity: Console.Verbosity {
        if quiet { return .quiet }
        if verbose { return .verbose }
        return .normal
    }

    /// A console configured from the flags.
    public var console: Console {
        Console(verbosity: verbosity)
    }
}

/// The `speechkit` root command.
///
/// Subcommands are listed here and nowhere else.
public struct SpeechKitCommand: AsyncParsableCommand {
    /// The command configuration, including the subcommand list.
    public static let configuration = CommandConfiguration(
        commandName: "speechkit",
        abstract: "Transcribe audio files with any SpeechKit provider.",
        version: "1.0.0",
        subcommands: [
            Transcribe.self, Bench.self, Stats.self, History.self,
            Providers.self, Languages.self, Keys.self, Voz.self, Interactive.self
        ],
        defaultSubcommand: Transcribe.self
    )

    /// Creates the root command.
    public init() {}

    /// Whether a bare `speechkit` should open the interactive mode.
    ///
    /// The check happens before ArgumentParser sees anything, because
    /// `transcribe` is the default subcommand and an empty argument list would
    /// otherwise parse as a `transcribe` with no files. Every other case is
    /// left exactly as it was, so `speechkit talk.wav -p voz` still transcribes
    /// and a no-argument run off a terminal still prints the usage error.
    ///
    /// - Parameters:
    ///   - arguments: The process arguments, without the executable name.
    ///   - isTTY: Whether standard input and standard error are both terminals.
    public static func wantsInteractive(arguments: [String], isTTY: Bool) -> Bool {
        arguments.isEmpty && isTTY
    }

    /// Parses the process arguments, runs the selected subcommand, and exits.
    ///
    /// This replaces `AsyncParsableCommand.main()` so the tool can use the exit
    /// codes documented in the README rather than ArgumentParser's defaults.
    public static func runMain() async -> Never {
        do {
            var command: any ParsableCommand
            if wantsInteractive(
                arguments: Array(CommandLine.arguments.dropFirst()),
                isTTY: Terminal.isInteractive()
            ) {
                // Parsed rather than constructed: an `@OptionGroup` only has
                // a value once ArgumentParser has filled it in.
                command = try Interactive.parse([])
            } else {
                command = try parseAsRoot()
            }
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
            Foundation.exit(0)
        } catch let error as CLIError {
            Console.writeStandardError("speechkit: \(error.localizedDescription)\n")
            Foundation.exit(error.exitCode)
        } catch {
            let message = FailureMessage.providerMessage(for: error) ?? fullMessage(for: error)
            let code = exitCode(for: error)
            if code == .success {
                if !message.isEmpty { print(message) }
                Foundation.exit(0)
            }
            if !message.isEmpty { Console.writeStandardError(message + "\n") }
            Foundation.exit(code == ExitCode.validationFailure ? 1 : code.rawValue)
        }
    }
}
