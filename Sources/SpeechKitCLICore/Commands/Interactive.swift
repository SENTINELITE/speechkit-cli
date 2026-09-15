import ArgumentParser
import Darwin
import Foundation

// MARK: - Choices

/// Where an interactive transcribe run writes its transcripts.
public enum InteractiveOutput: Equatable, Sendable {
    /// Standard output, offered only for one file in one format.
    case standardOutput
    /// The directory the first input file is in.
    case nextToInputs
    /// A directory the user typed.
    case directory(String)
}

/// Everything the transcribe flow collects.
public struct InteractiveTranscribeChoices: Equatable, Sendable {
    /// The input paths, as the user gave them.
    public var files: [String]
    /// The provider.
    public var provider: CLIProvider
    /// The formats to write.
    public var formats: [OutputFormat]
    /// Whether word timings were asked for.
    public var words: Bool
    /// Whether speaker labels were asked for.
    public var diarize: Bool
    /// Where transcripts go.
    public var output: InteractiveOutput

    /// Creates a set of choices.
    public init(
        files: [String],
        provider: CLIProvider,
        formats: [OutputFormat],
        words: Bool = false,
        diarize: Bool = false,
        output: InteractiveOutput = .nextToInputs
    ) {
        self.files = files
        self.provider = provider
        self.formats = formats
        self.words = words
        self.diarize = diarize
        self.output = output
    }

    /// Whether standard output is a legal destination for these choices.
    ///
    /// `transcribe` refuses stdout for several files or several formats,
    /// because two transcripts down one pipe cannot be told apart. The prompt
    /// therefore does not offer it rather than letting the run fail later.
    public var allowsStandardOutput: Bool {
        files.count == 1 && formats.count == 1
    }
}

/// Everything the bench flow collects.
public struct InteractiveBenchChoices: Equatable, Sendable {
    /// The input files and folders.
    public var inputs: [String]
    /// The `-p` values, which may be the single word `all`.
    public var providers: [String]
    /// The formats to write per provider.
    public var formats: [OutputFormat]
    /// The reference transcript directory, when one was given.
    public var referenceDirectory: String?
    /// How many times each file is transcribed per provider.
    public var repeatCount: Int
    /// Where the transcripts and the summaries go.
    public var outputDirectory: String

    /// Creates a set of choices.
    public init(
        inputs: [String],
        providers: [String],
        formats: [OutputFormat],
        referenceDirectory: String? = nil,
        repeatCount: Int = 1,
        outputDirectory: String
    ) {
        self.inputs = inputs
        self.providers = providers
        self.formats = formats
        self.referenceDirectory = referenceDirectory
        self.repeatCount = repeatCount
        self.outputDirectory = outputDirectory
    }
}

/// A headless command the interactive mode assembled.
///
/// The interactive mode never runs anything of its own: it fills this in and
/// hands the arguments to `Transcribe.parse(_:)` or `Bench.parse(_:)`, so
/// validation, output, history, and exit codes are the code paths a typed
/// command already goes through. ``displayLine`` is that same command written
/// out for the user to copy.
public struct InteractiveCommand: Equatable, Sendable {
    /// The subcommand name, such as `transcribe`.
    public let name: String
    /// The arguments after the subcommand name.
    public let arguments: [String]

    /// Creates a command.
    public init(name: String, arguments: [String]) {
        self.name = name
        self.arguments = arguments
    }

    /// The command as the user could paste it into a shell.
    public var displayLine: String {
        (["speechkit", name] + arguments.map(InteractiveCommand.quote)).joined(separator: " ")
    }

    /// The characters that never need quoting in a shell word.
    static let safeCharacters = Swift.Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-/:=@,+%")

    /// Returns an argument quoted for a shell.
    ///
    /// Single quotes are used rather than backslashes because a path with a
    /// space and a path with a parenthesis then read the same way, and the only
    /// special case is a single quote itself.
    public static func quote(_ argument: String) -> String {
        guard !argument.isEmpty else { return "''" }
        guard argument.contains(where: { !safeCharacters.contains($0) }) else { return argument }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Turns interactive choices into headless arguments.
public enum InteractiveArguments {
    /// Returns the `transcribe` command for a set of choices.
    ///
    /// Standard output is only ever assembled for one file in one format;
    /// anything else falls back to writing beside the inputs, which is what the
    /// prompt offers in that case.
    public static func transcribe(_ choices: InteractiveTranscribeChoices) -> InteractiveCommand {
        var arguments = choices.files
        arguments += ["-p", choices.provider.rawValue]
        for format in choices.formats {
            arguments += ["-f", format.rawValue]
        }
        if choices.words { arguments.append("--words") }
        if choices.diarize { arguments.append("--diarize") }

        switch choices.output {
        case .standardOutput where choices.allowsStandardOutput:
            break
        case .standardOutput, .nextToInputs:
            arguments += ["-o", directory(besideFirstOf: choices.files)]
        case .directory(let path):
            arguments += ["-o", trailingSlash(path)]
        }
        return InteractiveCommand(name: "transcribe", arguments: arguments)
    }

    /// Returns the `bench` command for a set of choices.
    public static func bench(_ choices: InteractiveBenchChoices) -> InteractiveCommand {
        var arguments = choices.inputs
        for provider in choices.providers {
            arguments += ["-p", provider]
        }
        for format in choices.formats {
            arguments += ["-f", format.rawValue]
        }
        if let reference = choices.referenceDirectory, !reference.isEmpty {
            arguments += ["--reference-dir", reference]
        }
        if choices.repeatCount > 1 {
            arguments += ["--repeat", String(choices.repeatCount)]
        }
        arguments += ["-o", trailingSlash(choices.outputDirectory)]
        return InteractiveCommand(name: "bench", arguments: arguments)
    }

    /// Returns the directory of the first input, as a `-o` value.
    ///
    /// "Next to the inputs" has no flag of its own, so it is spelled as the
    /// directory the first file is in. Files from several folders therefore
    /// land together, which is the same thing `-o` has always meant and is
    /// visible in the command the user is shown before anything runs.
    static func directory(besideFirstOf files: [String]) -> String {
        guard let first = files.first else { return "./" }
        let parent = (first as NSString).deletingLastPathComponent
        return parent.isEmpty ? "./" : trailingSlash(parent)
    }

    /// Returns a path that `--output` reads as a directory.
    static func trailingSlash(_ path: String) -> String {
        path.hasSuffix("/") ? path : path + "/"
    }
}

// MARK: - Status

/// The one-line status shown beside a provider in the picker.
public enum ProviderStatusText {
    /// Returns the status for a provider.
    ///
    /// - Parameters:
    ///   - provider: The provider being described.
    ///   - source: Where its credential would come from.
    ///   - vozCached: Whether the VOZ model is already on disk.
    ///   - appleAvailable: Whether this machine is new enough for Apple's
    ///     on-device transcriber.
    public static func text(
        for provider: CLIProvider,
        source: CredentialSource,
        vozCached: Bool,
        appleAvailable: Bool
    ) -> String {
        switch provider {
        case .voz:
            return vozCached ? "on device, ready" : "on device, model not downloaded"
        case .apple:
            return appleAvailable ? "on device, ready" : "on device, needs macOS 26"
        default:
            switch source {
            case .environment: return "key: env"
            case .keychain: return "key: keychain"
            case .notFound: return "no key"
            case .notNeeded: return "on device, ready"
            }
        }
    }

    /// Whether a provider named with this status can be run right now.
    public static func isRunnable(source: CredentialSource) -> Bool {
        source != .notFound
    }
}

// MARK: - Defaults

/// What the prompts are prefilled with.
public struct InteractiveDefaults: Equatable, Sendable {
    /// The provider of the most recent recorded run.
    public var provider: CLIProvider?
    /// The formats of the most recent recorded run.
    public var formats: [OutputFormat]
    /// The output directory of the most recent recorded run.
    public var outputDirectory: String?

    /// Creates a set of defaults.
    public init(
        provider: CLIProvider? = nil,
        formats: [OutputFormat] = [],
        outputDirectory: String? = nil
    ) {
        self.provider = provider
        self.formats = formats
        self.outputDirectory = outputDirectory
    }

    /// The defaults for a machine with no history at all.
    public static let empty = InteractiveDefaults()

    /// Returns the defaults implied by a history file.
    ///
    /// Only successful `transcribe` rows count. A failed run is not a
    /// preference, and a `bench` row names one provider out of several that
    /// were being compared, so neither says what to offer first.
    public static func fromHistory(_ records: [HistoryRecord]) -> InteractiveDefaults {
        let usable = records
            .filter { $0.command == "transcribe" && $0.succeeded }
            .sorted { $0.timestamp < $1.timestamp }
        guard let last = usable.last else { return .empty }
        return InteractiveDefaults(
            provider: CLIProvider(argument: last.provider),
            formats: last.formats.compactMap { OutputFormat(argument: $0) },
            outputDirectory: usable.last(where: { $0.outputDirectory != nil })?.outputDirectory
        )
    }

    /// Returns the provider to offer on a machine with no history.
    ///
    /// - Parameters:
    ///   - vozCached: Whether the VOZ model is already downloaded.
    ///   - appleAvailable: Whether Apple's on-device transcriber exists here.
    ///   - hasKey: Whether a provider has a usable credential.
    public static func firstRunProvider(
        vozCached: Bool,
        appleAvailable: Bool,
        hasKey: (CLIProvider) -> Bool
    ) -> CLIProvider {
        if vozCached { return .voz }
        if appleAvailable { return .apple }
        return CLIProvider.allCases.first { $0.requiresCredential && hasKey($0) } ?? .voz
    }
}

// MARK: - Files

/// Expands what the file prompts accept into paths.
public enum InteractiveFiles {
    /// Returns the paths a typed entry stands for.
    ///
    /// A shell would expand `*.wav` before the tool saw it, and inside a prompt
    /// there is no shell, so the same pattern is matched here with `fnmatch`.
    /// A pattern that matches nothing is returned unchanged, so the run fails
    /// naming what the user actually typed.
    public static func expand(_ entry: String) -> [String] {
        let trimmed = entry.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains(where: { "*?[".contains($0) }) else { return [trimmed] }

        let directory = (trimmed as NSString).deletingLastPathComponent
        let pattern = (trimmed as NSString).lastPathComponent
        let searched = directory.isEmpty ? "." : directory
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: searched)) ?? []
        let matched = entries
            .filter { fnmatch(pattern, $0, 0) == 0 }
            .sorted()
            .map { directory.isEmpty ? $0 : (directory as NSString).appendingPathComponent($0) }
        return matched.isEmpty ? [trimmed] : matched
    }
}

// MARK: - The command

/// Walks through provider, files, formats, and output on a terminal.
///
/// The flow ends by printing the headless command the answers produce and
/// running that, so nothing here is a second implementation of anything:
/// `transcribe` and `bench` are parsed from arguments and run exactly as if
/// they had been typed.
public struct Interactive: AsyncParsableCommand {
    /// The command configuration.
    public static let configuration = CommandConfiguration(
        commandName: "interactive",
        abstract: "Choose a provider, files, and formats with arrow keys.",
        discussion: """
        Started automatically by 'speechkit' with no arguments on a terminal. \
        Arrow keys move, enter chooses, space toggles, escape goes back a step, \
        and Ctrl-C leaves. The command your answers produce is printed before it \
        runs, so it can be pasted into a script.
        """,
        aliases: ["ui"]
    )

    /// Global verbosity flags.
    @OptionGroup public var globals: GlobalOptions

    /// Creates the command.
    public init() {}

    /// The message printed when there is no terminal to prompt on.
    public static let notATerminalMessage =
        "Interactive mode needs a terminal on standard input and standard error. "
        + "Run 'speechkit transcribe <file> -p <provider>', or 'speechkit --help'."

    /// Runs the interactive session.
    public func run() async throws {
        guard Terminal.isInteractive() else {
            throw CLIError.usage(Self.notATerminalMessage)
        }
        let terminal = Terminal()
        try terminal.enterRawMode()
        defer { terminal.restore() }
        terminal.hideCursor()
        try await InteractiveSession(terminal: terminal, console: globals.console).run()
    }
}

// MARK: - The session

/// Drives the prompts, assembles the command, and runs it.
final class InteractiveSession {
    /// Thrown by `Ctrl-C` and `Ctrl-D`, and turned into exit code 130.
    struct Cancelled: Error {}

    /// The identifier of the row that opens a path prompt.
    static let enterPathID = "\u{1}path"

    private let terminal: Terminal
    private let runner: PromptRunner
    private let console: Console
    private let environment: [String: String]
    private let store: KeychainStore
    private var defaults: InteractiveDefaults = .empty
    private var vozCached = false

    /// Creates a session.
    ///
    /// - Parameters:
    ///   - terminal: The terminal, already in raw mode.
    ///   - console: The console the run itself reports on.
    init(terminal: Terminal, console: Console) {
        self.terminal = terminal
        self.console = console
        self.environment = ProcessInfo.processInfo.environment
        self.store = KeychainStore()
        self.runner = PromptRunner(reader: terminal)
    }

    /// Whether Apple's on-device transcriber exists on this machine.
    var appleAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    // MARK: Entry

    /// Asks what to do, runs that flow, and leaves.
    func run() async throws {
        do {
            try await start()
        } catch is Cancelled {
            terminal.restore()
            throw ExitCode(130)
        }
    }

    private func start() async throws {
        defaults = await Self.loadDefaults()
        vozCached = await VozModelSession().isModelCached()

        runner.note(
            "speechkit \(SpeechKitCommand.configuration.version)  "
            + "arrows move, enter chooses, space toggles, escape goes back, Ctrl-C leaves."
        )

        while true {
            let action = SelectPrompt(
                title: "What do you want to do?",
                items: [
                    SelectItem(id: "transcribe", title: "Transcribe files"),
                    SelectItem(id: "bench", title: "Benchmark providers"),
                    SelectItem(id: "keys", title: "Manage keys"),
                    SelectItem(id: "voz", title: "Prepare VOZ")
                ]
            )
            guard let choice = try ask(action) else { return }
            let finished: Bool
            switch choice {
            case "transcribe": finished = try await transcribeFlow()
            case "bench": finished = try await benchFlow()
            case "keys": finished = try keysFlow(for: nil)
            default: finished = try await vozFlow()
            }
            if finished { return }
        }
    }

    /// Reads the history for the prefilled answers.
    ///
    /// A history that cannot be read is not an error here: the defaults are
    /// a convenience, so an unreadable or absent file simply means the first
    /// run fallbacks are used.
    static func loadDefaults() async -> InteractiveDefaults {
        let store = HistoryStore()
        guard let result = try? await store.read() else { return .empty }
        return InteractiveDefaults.fromHistory(result.records)
    }

    // MARK: Prompt helpers

    /// Runs a prompt, turning cancellation into a thrown error.
    ///
    /// - Returns: The answer, or `nil` when escape stepped back.
    private func ask<P: Prompt>(_ prompt: P) throws -> P.Value? {
        switch runner.run(prompt) {
        case .submit(let value): return value
        case .back, .continue: return nil
        case .cancel: throw Cancelled()
        }
    }

    // MARK: Transcribe

    /// The prompts of the transcribe flow, in order.
    private enum TranscribeStep {
        case provider, files, formats, words, diarize, output, confirm
    }

    /// Runs the transcribe flow.
    ///
    /// - Returns: `true` when the session is over, `false` to go back to the
    ///   first question.
    private func transcribeFlow() async throws -> Bool {
        var provider = defaults.provider ?? InteractiveDefaults.firstRunProvider(
            vozCached: vozCached,
            appleAvailable: appleAvailable,
            hasKey: { credentialSource(for: $0) != .notFound }
        )
        var files: [String] = []
        var formats = defaults.formats.isEmpty ? [OutputFormat.txt] : defaults.formats
        var words = false
        var diarize = false
        var output: InteractiveOutput = defaults.outputDirectory.map { .directory($0) } ?? .nextToInputs

        var steps = Self.steps(for: provider)
        var index = 0
        while index < steps.count {
            var advanced = true
            switch steps[index] {
            case .provider:
                guard let chosen = try askProvider(current: provider) else { return false }
                provider = chosen
                steps = Self.steps(for: provider)
                if try !prepared(provider) {
                    advanced = false
                    break
                }
                if !ProviderCapabilities.capabilities(for: provider).supportsWordTimestamps { words = false }
                if !ProviderCapabilities.capabilities(for: provider).supportsDiarization { diarize = false }
            case .files:
                guard let chosen = try askFiles() else {
                    advanced = false
                    break
                }
                files = chosen
            case .formats:
                guard let chosen = try askFormats(current: formats) else {
                    advanced = false
                    break
                }
                formats = chosen
            case .words:
                guard let chosen = try ask(ConfirmPrompt(title: "Word timestamps?", value: words)) else {
                    advanced = false
                    break
                }
                words = chosen
            case .diarize:
                guard let chosen = try ask(ConfirmPrompt(title: "Speaker labels?", value: diarize)) else {
                    advanced = false
                    break
                }
                diarize = chosen
            case .output:
                let choices = InteractiveTranscribeChoices(
                    files: files, provider: provider, formats: formats, output: output
                )
                guard let chosen = try askOutput(current: output, allowsStandardOutput: choices.allowsStandardOutput) else {
                    advanced = false
                    break
                }
                output = chosen
            case .confirm:
                let command = InteractiveArguments.transcribe(
                    InteractiveTranscribeChoices(
                        files: files,
                        provider: provider,
                        formats: formats,
                        words: words,
                        diarize: diarize,
                        output: output
                    )
                )
                guard try confirm(command) else {
                    advanced = false
                    break
                }
                try await execute(command)
                return true
            }
            index += advanced ? 1 : -1
            if index < 0 { return false }
        }
        return false
    }

    /// The steps a provider's capabilities call for.
    ///
    /// A provider that cannot time words or label speakers is never asked
    /// about them, so the form has no question whose only answer is no.
    private static func steps(for provider: CLIProvider) -> [TranscribeStep] {
        let capabilities = ProviderCapabilities.capabilities(for: provider)
        var steps: [TranscribeStep] = [.provider, .files, .formats]
        if capabilities.supportsWordTimestamps { steps.append(.words) }
        if capabilities.supportsDiarization { steps.append(.diarize) }
        return steps + [.output, .confirm]
    }

    // MARK: Prompts

    /// Asks for a provider, with its credential or model status beside it.
    private func askProvider(current: CLIProvider?) throws -> CLIProvider? {
        let items = CLIProvider.allCases.map { provider in
            SelectItem(
                id: provider.rawValue,
                title: provider.rawValue,
                detail: ProviderStatusText.text(
                    for: provider,
                    source: credentialSource(for: provider),
                    vozCached: vozCached,
                    appleAvailable: appleAvailable
                )
            )
        }
        let prompt = SelectPrompt(title: "Provider", items: items, selectedID: current?.rawValue)
        guard let chosen = try ask(prompt) else { return nil }
        return CLIProvider(argument: chosen)
    }

    /// Makes sure the chosen provider can run, asking for what it is missing.
    ///
    /// A provider with no key drops into the key flow and comes back; VOZ with
    /// no model on disk asks before several hundred megabytes are fetched. Both
    /// answer `false` when the provider is still not usable, which puts the
    /// picker back on screen rather than failing several prompts later.
    private func prepared(_ provider: CLIProvider) throws -> Bool {
        if provider.requiresCredential, credentialSource(for: provider) == .notFound {
            try keysFlow(for: provider)
            return credentialSource(for: provider) != .notFound
        }
        if provider == .voz, !vozCached {
            let prompt = ConfirmPrompt(
                title: "The VOZ model is not downloaded. Fetch \(VozModelSession.downloadSize) now?",
                value: true
            )
            guard let yes = try ask(prompt), yes else { return false }
        }
        return true
    }

    /// Asks which files to transcribe.
    ///
    /// The audio files in the current directory are listed when there are any,
    /// because that is where the recordings usually are, and a row at the end
    /// opens a path prompt for everything else.
    private func askFiles() throws -> [String]? {
        let found = AudioFileFinder.audioFiles(in: URL(fileURLWithPath: "."), recursive: false)
        guard !found.isEmpty else {
            guard let path = try askPath(title: "Files") else { return nil }
            return InteractiveFiles.expand(path)
        }

        var items = found.map { SelectItem(id: $0.lastPathComponent, title: $0.lastPathComponent) }
        items.append(SelectItem(id: Self.enterPathID, title: "Enter a path…"))
        guard let chosen = try ask(MultiSelectPrompt(title: "Files", items: items)) else { return nil }

        var files = chosen.filter { $0 != Self.enterPathID }
        if chosen.contains(Self.enterPathID) {
            guard let path = try askPath(title: "Path") else { return nil }
            files += InteractiveFiles.expand(path)
        }
        return files.isEmpty ? nil : files
    }

    /// Asks for a path, completing against the file system.
    private func askPath(title: String, text: String = "") throws -> String? {
        try ask(PathPrompt(title: title, text: text))
    }

    /// Asks which formats to write.
    private func askFormats(current: [OutputFormat]) throws -> [OutputFormat]? {
        let items = OutputFormat.allCases.map { SelectItem($0.rawValue) }
        let prompt = MultiSelectPrompt(
            title: "Formats",
            items: items,
            selectedIDs: current.map(\.rawValue)
        )
        guard let chosen = try ask(prompt) else { return nil }
        return chosen.compactMap { OutputFormat(argument: $0) }
    }

    /// Asks where the transcripts go.
    private func askOutput(current: InteractiveOutput, allowsStandardOutput: Bool) throws -> InteractiveOutput? {
        var items: [SelectItem] = []
        if allowsStandardOutput {
            items.append(SelectItem(id: "stdout", title: "stdout"))
        }
        items.append(SelectItem(id: "beside", title: "next to the inputs"))
        items.append(SelectItem(id: "directory", title: "choose a directory…"))

        let selected: String
        switch current {
        case .standardOutput: selected = allowsStandardOutput ? "stdout" : "beside"
        case .nextToInputs: selected = "beside"
        case .directory: selected = "directory"
        }

        guard let chosen = try ask(SelectPrompt(title: "Output", items: items, selectedID: selected)) else {
            return nil
        }
        switch chosen {
        case "stdout":
            return .standardOutput
        case "beside":
            return .nextToInputs
        default:
            let text: String
            if case .directory(let existing) = current { text = existing } else { text = "" }
            guard let path = try askPath(title: "Directory", text: text) else { return nil }
            return .directory(path)
        }
    }

    /// Shows the assembled command and asks what to do with it.
    ///
    /// - Returns: `true` to run it, `false` to go back a step. Copying leaves
    ///   the question on screen, because a copied command is usually the answer
    ///   to "what flag was that?" and the run still has to be decided.
    private func confirm(_ command: InteractiveCommand) throws -> Bool {
        while true {
            runner.note("")
            runner.note("  " + command.displayLine)
            runner.note("")
            let prompt = SelectPrompt(
                title: "Run it?",
                items: [
                    SelectItem(id: "run", title: "Yes"),
                    SelectItem(id: "copy", title: "Copy command"),
                    SelectItem(id: "back", title: "Back")
                ]
            )
            guard let chosen = try ask(prompt) else { return false }
            switch chosen {
            case "run":
                return true
            case "copy":
                Self.copyToClipboard(command.displayLine)
                runner.note("Copied.")
            default:
                return false
            }
        }
    }

    // MARK: Bench

    /// Runs the benchmark flow.
    private func benchFlow() async throws -> Bool {
        var providers: [String] = ["all"]
        var inputs: [String] = []
        var formats = [OutputFormat.txt]
        var reference: String?
        var repeatCount = 1
        var directory = "./bench"

        var index = 0
        while index < 6 {
            var advanced = true
            switch index {
            case 0:
                var items = [SelectItem(id: "all", title: "all")]
                items += CLIProvider.allCases.map { provider in
                    SelectItem(
                        id: provider.rawValue,
                        title: provider.rawValue,
                        detail: ProviderStatusText.text(
                            for: provider,
                            source: credentialSource(for: provider),
                            vozCached: vozCached,
                            appleAvailable: appleAvailable
                        )
                    )
                }
                guard let chosen = try ask(
                    MultiSelectPrompt(title: "Providers", items: items, selectedIDs: providers)
                ) else { return false }
                // `all` already means every provider with a credential, so it
                // is never combined with a name.
                providers = chosen.contains("all") ? ["all"] : chosen
            case 1:
                guard let chosen = try askFiles() else {
                    advanced = false
                    break
                }
                inputs = chosen
            case 2:
                guard let chosen = try askFormats(current: formats) else {
                    advanced = false
                    break
                }
                formats = chosen
            case 3:
                guard let wants = try ask(
                    ConfirmPrompt(title: "Score against reference transcripts?", value: reference != nil)
                ) else {
                    advanced = false
                    break
                }
                if wants {
                    guard let path = try askPath(title: "Reference directory", text: reference ?? "") else {
                        advanced = false
                        break
                    }
                    reference = path
                } else {
                    reference = nil
                }
            case 4:
                guard let text = try ask(
                    TextPrompt(title: "Repeat count", defaultValue: String(repeatCount))
                ) else {
                    advanced = false
                    break
                }
                repeatCount = max(1, Int(text.trimmingCharacters(in: .whitespaces)) ?? 1)
            default:
                guard let path = try askPath(title: "Output directory", text: directory) else {
                    advanced = false
                    break
                }
                directory = path
                let command = InteractiveArguments.bench(
                    InteractiveBenchChoices(
                        inputs: inputs,
                        providers: providers,
                        formats: formats,
                        referenceDirectory: reference,
                        repeatCount: repeatCount,
                        outputDirectory: directory
                    )
                )
                guard try confirm(command) else {
                    advanced = false
                    break
                }
                try await execute(command)
                return true
            }
            index += advanced ? 1 : -1
            if index < 0 { return false }
        }
        return false
    }

    // MARK: Keys and VOZ

    /// Stores a key for one provider, through the same code `keys set` uses.
    ///
    /// - Parameter provider: The provider to set a key for, or `nil` to ask.
    /// - Returns: `true` when the session is over, which it is when the flow
    ///   was entered from the first question rather than from the picker.
    @discardableResult
    private func keysFlow(for provider: CLIProvider?) throws -> Bool {
        let entered = provider == nil
        let target: CLIProvider
        if let provider {
            target = provider
        } else {
            let items = CLIProvider.allCases.filter(\.requiresCredential).map { candidate in
                SelectItem(
                    id: candidate.rawValue,
                    title: candidate.rawValue,
                    detail: ProviderStatusText.text(
                        for: candidate,
                        source: credentialSource(for: candidate),
                        vozCached: vozCached,
                        appleAvailable: appleAvailable
                    )
                )
            }
            guard let chosen = try ask(SelectPrompt(title: "Provider", items: items)),
                  let picked = CLIProvider(argument: chosen) else {
                return false
            }
            target = picked
        }

        let prompt = TextPrompt(title: "API key for \(target.rawValue)", isSecret: true)
        guard let key = try ask(prompt) else { return false }
        do {
            runner.note(try KeysRunner(store: store, environment: environment, console: console).set(key, for: target))
        } catch {
            runner.note("speechkit: \(error.localizedDescription)")
        }
        return entered
    }

    /// Downloads and loads the VOZ model, through the same code `voz prepare` uses.
    private func vozFlow() async throws -> Bool {
        if vozCached {
            runner.note("The VOZ model is already downloaded.")
            return false
        }
        let prompt = ConfirmPrompt(
            title: "Download the VOZ model (\(VozModelSession.downloadSize))?",
            value: true
        )
        guard let yes = try ask(prompt), yes else { return false }

        terminal.restore()
        let command = try Voz.Prepare.parse([])
        try await command.run()
        return true
    }

    // MARK: Running

    /// Parses the assembled arguments and runs the real command.
    ///
    /// Raw mode is given up first, so the run's own progress rows, warnings,
    /// and `Ctrl-C` behave exactly as they do for a typed command.
    private func execute(_ command: InteractiveCommand) async throws {
        terminal.restore()
        switch command.name {
        case "bench":
            let bench = try Bench.parse(command.arguments)
            try await bench.run()
        default:
            let transcribe = try Transcribe.parse(command.arguments)
            try await transcribe.run()
        }
    }

    // MARK: Helpers

    /// Where a provider's credential would come from right now.
    private func credentialSource(for provider: CLIProvider) -> CredentialSource {
        CredentialCheck(environment: environment, store: store).credential(for: provider).source
    }

    /// Puts text on the clipboard with `pbcopy`.
    ///
    /// A failure is silent: the command is on screen either way, and a shell
    /// without `pbcopy` is not a reason to interrupt the flow.
    static func copyToClipboard(_ text: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
        let pipe = Pipe()
        process.standardInput = pipe
        guard (try? process.run()) != nil else { return }
        pipe.fileHandleForWriting.write(Data(text.utf8))
        try? pipe.fileHandleForWriting.close()
        process.waitUntilExit()
    }
}
