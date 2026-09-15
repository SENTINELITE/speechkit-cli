import ArgumentParser
import Foundation

/// Where the credential for a provider would come from on this machine right now.
public enum CredentialSource: String, Sendable, Codable, Equatable {
    /// The provider needs no credential.
    case notNeeded = "not needed"
    /// A `SPEECHKIT_<PROVIDER>_API_KEY` variable is set.
    case environment = "env"
    /// A key is stored in the keychain.
    case keychain
    /// Nothing was found.
    ///
    /// The case is spelled `notFound` rather than `none` so it is never
    /// mistaken for `Optional.none` at a use site.
    case notFound = "none"
}

/// One row of the provider capability table.
public struct ProviderReport: Sendable, Codable, Equatable {
    /// The `--provider` value.
    public let provider: String
    /// The model used for file transcription when `--model` is absent.
    public let defaultFileModel: String?
    /// Whether the provider returns word-level timestamps.
    public let wordTimestamps: Bool
    /// Whether the provider returns timed segments, which subtitles need.
    public let segments: Bool
    /// Whether the provider labels speakers.
    public let diarization: Bool
    /// How the provider expects `--language` values.
    public let languageStyle: String
    /// The upload size limit in bytes, when the provider has one.
    public let maxFileBytes: Int64?
    /// The file extensions the provider accepts, when it checks them.
    public let acceptedExtensions: [String]?
    /// The lowest macOS version the provider runs on.
    public let minimumMacOS: String
    /// Where a credential was found on this machine.
    public let credentialSource: CredentialSource

    /// Builds the report for one provider.
    ///
    /// - Parameters:
    ///   - provider: The provider to describe.
    ///   - environment: The environment consulted for `SPEECHKIT_*_API_KEY`.
    ///   - store: The keychain consulted when the environment has nothing.
    public init(
        provider: CLIProvider,
        environment: [String: String],
        store: (any KeychainStoring)?
    ) {
        let capabilities = ProviderCapabilities.capabilities(for: provider)
        self.provider = provider.rawValue
        self.defaultFileModel = capabilities.defaultFileModel
        self.wordTimestamps = capabilities.supportsWordTimestamps
        self.segments = capabilities.supportsSegments
        self.diarization = capabilities.supportsDiarization
        self.languageStyle = capabilities.languageStyle.rawValue
        self.maxFileBytes = capabilities.maxFileBytes
        self.acceptedExtensions = capabilities.acceptedExtensions
        self.minimumMacOS = capabilities.requiresMacOS26 ? "26" : "15"
        self.credentialSource = Self.credentialSource(
            for: provider,
            environment: environment,
            store: store
        )
    }

    private static func credentialSource(
        for provider: CLIProvider,
        environment: [String: String],
        store: (any KeychainStoring)?
    ) -> CredentialSource {
        guard provider != .apple else { return .notNeeded }
        let variable = CredentialResolver.environmentVariableName(for: provider)
        if let value = environment[variable]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            return .environment
        }
        if let stored = try? store?.read(for: provider) ?? nil, !stored.isEmpty {
            return .keychain
        }
        return .notFound
    }

    /// Reports every provider in the order `--provider` lists them.
    public static func all(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        store: (any KeychainStoring)? = KeychainStore()
    ) -> [ProviderReport] {
        CLIProvider.allCases.map { ProviderReport(provider: $0, environment: environment, store: store) }
    }

    /// Renders reports as a fixed-width ASCII table.
    ///
    /// The extension list is last because it is the only variable-length
    /// column, which keeps the rest of the table aligned on narrow terminals.
    public static func table(_ reports: [ProviderReport]) -> String {
        let rows = reports.map { report -> [String] in
            [
                report.provider,
                report.defaultFileModel ?? "-",
                report.wordTimestamps ? "yes" : "no",
                report.segments ? "yes" : "no",
                report.diarization ? "yes" : "no",
                report.languageStyle,
                report.maxFileBytes.map(byteSize) ?? "-",
                report.minimumMacOS,
                report.credentialSource.rawValue,
                report.acceptedExtensions?.joined(separator: ",") ?? "any"
            ]
        }
        return TextTable(
            headers: [
                "provider", "default model", "words", "segments", "diarize",
                "language", "max size", "macos", "credential", "extensions"
            ],
            rows: rows
        ).render()
    }

    /// Formats a byte limit in whole binary units.
    static func byteSize(_ bytes: Int64) -> String {
        let units: [(name: String, size: Int64)] = [
            ("GB", 1024 * 1024 * 1024),
            ("MB", 1024 * 1024),
            ("KB", 1024)
        ]
        for unit in units where bytes >= unit.size {
            let whole = bytes / unit.size
            return bytes % unit.size == 0 ? "\(whole) \(unit.name)" : String(
                format: "%.1f %@",
                Double(bytes) / Double(unit.size),
                unit.name
            )
        }
        return "\(bytes) B"
    }
}

/// Prints what each provider can do and where its credential would come from.
public struct Providers: ParsableCommand {
    /// The command configuration.
    public static let configuration = CommandConfiguration(
        commandName: "providers",
        abstract: "Show provider capabilities and where each credential comes from."
    )

    /// Emits an array of objects instead of a table.
    @Flag(name: .long, help: "Emit JSON instead of a table.")
    public var json: Bool = false

    /// Global verbosity flags.
    @OptionGroup public var globals: GlobalOptions

    /// Creates an empty command.
    public init() {}

    /// Runs the command.
    public func run() throws {
        let reports = ProviderReport.all()
        let text: String
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            text = String(decoding: try encoder.encode(reports), as: UTF8.self) + "\n"
        } else {
            text = ProviderReport.table(reports)
        }
        FileHandle.standardOutput.write(Data(text.utf8))
    }
}
