import ArgumentParser
import Darwin
import Foundation

/// Stores, reads, and removes provider API keys in the login keychain.
public struct Keys: ParsableCommand {
    /// The command configuration.
    public static let configuration = CommandConfiguration(
        commandName: "keys",
        abstract: "Store provider API keys in the macOS keychain.",
        subcommands: [Set.self, Get.self, Delete.self, List.self],
        defaultSubcommand: List.self
    )

    /// Creates the command.
    public init() {}

    /// Stores an API key for one provider.
    public struct Set: ParsableCommand {
        /// The command configuration.
        public static let configuration = CommandConfiguration(
            commandName: "set",
            abstract: "Store an API key. Prompts without echo, or reads stdin with --from-stdin."
        )

        /// The provider the key belongs to.
        @Argument(help: "Provider: \(CLIProvider.allValueStrings.joined(separator: ", ")).")
        public var provider: CLIProvider

        /// Reads the key from standard input instead of prompting.
        @Flag(name: .long, help: "Read the key from standard input, for scripts.")
        public var fromStdin: Bool = false

        /// Global verbosity flags.
        @OptionGroup public var globals: GlobalOptions

        /// Creates an empty command.
        public init() {}

        /// Runs the command.
        public func run() throws {
            let runner = KeysRunner(console: globals.console)
            let key = try runner.readKey(for: provider, fromStandardInput: fromStdin)
            print(try runner.set(key, for: provider))
        }
    }

    /// Prints the stored API key for one provider, redacted by default.
    public struct Get: ParsableCommand {
        /// The command configuration.
        public static let configuration = CommandConfiguration(
            commandName: "get",
            abstract: "Print a stored API key, redacted unless --reveal is passed."
        )

        /// The provider to read.
        @Argument(help: "Provider: \(CLIProvider.allValueStrings.joined(separator: ", ")).")
        public var provider: CLIProvider

        /// Prints the key in full.
        @Flag(name: .long, help: "Print the key in full.")
        public var reveal: Bool = false

        /// Global verbosity flags.
        @OptionGroup public var globals: GlobalOptions

        /// Creates an empty command.
        public init() {}

        /// Runs the command.
        public func run() throws {
            print(try KeysRunner(console: globals.console).get(provider, reveal: reveal))
        }
    }

    /// Removes the stored API key for one provider.
    public struct Delete: ParsableCommand {
        /// The command configuration.
        public static let configuration = CommandConfiguration(
            commandName: "delete",
            abstract: "Remove a stored API key."
        )

        /// The provider to remove.
        @Argument(help: "Provider: \(CLIProvider.allValueStrings.joined(separator: ", ")).")
        public var provider: CLIProvider

        /// Global verbosity flags.
        @OptionGroup public var globals: GlobalOptions

        /// Creates an empty command.
        public init() {}

        /// Runs the command.
        public func run() throws {
            print(try KeysRunner(console: globals.console).delete(provider))
        }
    }

    /// Lists every provider, whether a key is stored, and any environment override.
    public struct List: ParsableCommand {
        /// The command configuration.
        public static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List providers, stored keys, and environment overrides."
        )

        /// Global verbosity flags.
        @OptionGroup public var globals: GlobalOptions

        /// Creates an empty command.
        public init() {}

        /// Runs the command.
        public func run() throws {
            FileHandle.standardOutput.write(Data(try KeysRunner(console: globals.console).list().utf8))
        }
    }
}

/// The behaviour behind `speechkit keys`, with storage injected.
///
/// The subcommands are thin wrappers over this type so tests can drive every
/// path against an in-memory store rather than the login keychain.
public struct KeysRunner: Sendable {
    /// The message printed when a key operation names Apple.
    public static let appleMessage = keylessMessage(.apple)

    /// The refusal for a provider that transcribes on device.
    public static func keylessMessage(_ provider: CLIProvider) -> String {
        "\(provider.rawValue) needs no key"
    }

    private let store: any KeychainStoring
    private let environment: [String: String]
    private let console: Console

    /// Creates a runner.
    ///
    /// - Parameters:
    ///   - store: Where keys are kept. Defaults to the login keychain.
    ///   - environment: The environment consulted for overrides.
    ///   - console: The console warnings are written to.
    public init(
        store: any KeychainStoring = KeychainStore(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        console: Console = Console()
    ) {
        self.store = store
        self.environment = environment
        self.console = console
    }

    /// Stores a key and returns the line to print.
    ///
    /// - Throws: ``CLIError/usage(_:)`` for Apple or an empty key, or
    ///   ``CLIError/keychainFailure(_:)`` when the write fails.
    public func set(_ key: String, for provider: CLIProvider) throws -> String {
        try requireKeyedProvider(provider)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CLIError.usage("The key is empty; nothing was stored.")
        }
        try store.save(trimmed, for: provider)
        if environment[CredentialResolver.environmentVariableName(for: provider)] != nil {
            console.warning(
                "\(CredentialResolver.environmentVariableName(for: provider)) is set and takes precedence over the keychain."
            )
        }
        return "Stored a \(provider.rawValue) key (\(trimmed.redactedAPIKey))."
    }

    /// Returns the stored key, redacted unless `reveal` is `true`.
    ///
    /// - Throws: ``CLIError/usage(_:)`` for Apple or when no key is stored.
    public func get(_ provider: CLIProvider, reveal: Bool) throws -> String {
        try requireKeyedProvider(provider)
        guard let key = try store.read(for: provider) else {
            throw CLIError.usage("No \(provider.rawValue) key is stored. Run 'speechkit keys set \(provider.rawValue)'.")
        }
        return reveal ? key : key.redactedAPIKey
    }

    /// Removes the stored key and returns the line to print.
    ///
    /// - Throws: ``CLIError/usage(_:)`` for Apple or when no key is stored.
    public func delete(_ provider: CLIProvider) throws -> String {
        try requireKeyedProvider(provider)
        guard try store.delete(for: provider) else {
            throw CLIError.usage("No \(provider.rawValue) key is stored.")
        }
        return "Deleted the \(provider.rawValue) key."
    }

    /// Returns the provider table for `keys list`.
    public func list() throws -> String {
        let stored = Swift.Set(try store.list())
        let rows = CLIProvider.allCases.map { provider -> [String] in
            let variable = CredentialResolver.environmentVariableName(for: provider)
            guard provider.requiresCredential else {
                return [provider.rawValue, "n/a", "-"]
            }
            let override = environment[variable]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty == false ? variable : "-"
            return [provider.rawValue, stored.contains(provider) ? "yes" : "no", override]
        }
        return TextTable(headers: ["provider", "stored", "environment override"], rows: rows).render()
    }

    /// Reads a key for `keys set`, from standard input or a hidden prompt.
    ///
    /// - Parameters:
    ///   - provider: The provider named on the command line, used in the prompt.
    ///   - fromStandardInput: Whether `--from-stdin` was passed.
    /// - Throws: ``CLIError/usage(_:)`` when there is no terminal to prompt on,
    ///   or when the prompt is cancelled.
    public func readKey(for provider: CLIProvider, fromStandardInput: Bool) throws -> String {
        if fromStandardInput {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            return String(decoding: data, as: UTF8.self)
        }
        guard isatty(FileHandle.standardInput.fileDescriptor) == 1 else {
            throw CLIError.usage(
                "Standard input is not a terminal. Pass --from-stdin to read the key from a pipe."
            )
        }
        guard let key = Self.promptWithoutEcho("API key for \(provider.rawValue): ") else {
            throw CLIError.usage("Could not read the key from the terminal.")
        }
        return key
    }

    /// Prompts on the terminal with echo turned off.
    ///
    /// `readpassphrase` is used rather than `getpass` because it reads and
    /// writes `/dev/tty` directly, so the prompt still works when standard
    /// output is redirected, and it restores the terminal on interrupt.
    static func promptWithoutEcho(_ prompt: String) -> String? {
        let capacity = 4096
        var buffer = [CChar](repeating: 0, count: capacity)
        defer {
            // Overwrite the copy in this process before the buffer is freed.
            for index in buffer.indices { buffer[index] = 0 }
        }
        guard readpassphrase(prompt, &buffer, capacity, Int32(RPP_REQUIRE_TTY)) != nil else {
            return nil
        }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func requireKeyedProvider(_ provider: CLIProvider) throws {
        guard provider.requiresCredential else {
            throw CLIError.usage(Self.keylessMessage(provider))
        }
    }
}
