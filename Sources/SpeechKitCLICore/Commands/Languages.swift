import ArgumentParser
import Foundation
import Speech

/// The `--language` values one provider accepts.
public struct LanguageReport: Sendable, Codable, Equatable {
    /// The `--provider` value.
    public let provider: String
    /// How the provider expects language values.
    public let style: String
    /// A sentence describing what the provider does with `--language`.
    public let note: String
    /// The accepted values, when the provider has a fixed list.
    public let values: [String]

    /// Creates a report.
    public init(provider: String, style: String, note: String, values: [String]) {
        self.provider = provider
        self.style = style
        self.note = note
        self.values = values
    }

    /// Builds the report for a provider.
    ///
    /// - Parameters:
    ///   - provider: The provider to describe.
    ///   - appleLocales: Identifiers from `SpeechTranscriber.supportedLocales`,
    ///     which only the caller can gather because the property is
    ///     asynchronous and needs macOS 26.
    public static func make(for provider: CLIProvider, appleLocales: [String]? = nil) -> LanguageReport {
        let style = ProviderCapabilities.capabilities(for: provider).languageStyle.rawValue
        switch provider {
        case .grok, .aqua, .cohere, .meta:
            return LanguageReport(
                provider: provider.rawValue,
                style: style,
                note: "\(provider.rawValue) accepts only these values. A region subtag such as -US is dropped before the match.",
                values: LanguageMapping.validValues(for: provider) ?? []
            )
        case .openai:
            return LanguageReport(
                provider: provider.rawValue,
                style: style,
                note: "openai accepts any BCP-47 or ISO 639-1 code, so there is no fixed list. Repeat --language to send several.",
                values: []
            )
        case .gemini:
            return LanguageReport(
                provider: provider.rawValue,
                style: style,
                note: "gemini accepts any BCP-47 code, so there is no fixed list. Repeat --language to send several.",
                values: []
            )
        case .fishAudio:
            return LanguageReport(
                provider: provider.rawValue,
                style: style,
                note: "fish-audio takes one two-letter ISO 639-1 hint such as en; a region subtag is dropped. The hint helps detection but does not force the language, and only the first --language is sent.",
                values: []
            )
        case .elevenlabs:
            return LanguageReport(
                provider: provider.rawValue,
                style: style,
                note: "elevenlabs Scribe detects the language itself; --language is ignored with a warning.",
                values: []
            )
        case .voz:
            return LanguageReport(
                provider: provider.rawValue,
                style: style,
                note: "voz runs one multilingual model that does not take a language hint and does not report the language it heard; --language is ignored with a warning.",
                values: []
            )
        case .apple:
            if let appleLocales {
                return LanguageReport(
                    provider: provider.rawValue,
                    style: style,
                    note: "apple accepts a Locale identifier, checked against the locales this machine's transcriber supports. On macOS 15 there is no local transcriber, so 'speechkit transcribe --provider apple' exits with code 3 there.",
                    values: appleLocales
                )
            }
            return LanguageReport(
                provider: provider.rawValue,
                style: style,
                note: "apple local transcription needs macOS 26 or later, so this machine can report no supported locales.",
                values: []
            )
        }
    }

    /// Renders the report as text.
    public func render() -> String {
        var text = note + "\n"
        if !values.isEmpty {
            text += "\n" + values.joined(separator: "\n") + "\n"
        }
        return text
    }
}

/// Prints the `--language` values a provider accepts.
public struct Languages: AsyncParsableCommand {
    /// The command configuration.
    public static let configuration = CommandConfiguration(
        commandName: "languages",
        abstract: "Show the --language values a provider accepts."
    )

    /// The provider to describe.
    @Argument(help: "Provider: \(CLIProvider.allValueStrings.joined(separator: ", ")).")
    public var provider: CLIProvider

    /// Emits an object instead of text.
    @Flag(name: .long, help: "Emit JSON instead of text.")
    public var json: Bool = false

    /// Global verbosity flags.
    @OptionGroup public var globals: GlobalOptions

    /// Creates an empty command.
    public init() {}

    /// Runs the command.
    public func run() async throws {
        let report = LanguageReport.make(for: provider, appleLocales: await Self.appleLocales(for: provider))
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

    /// Returns the locales Apple's transcriber supports, or `nil` off Apple and on older systems.
    ///
    /// SpeechKit exposes no supported-locale accessor, so the Speech framework
    /// is asked directly. The property is asynchronous because the list depends
    /// on assets the system may still be cataloguing.
    static func appleLocales(for provider: CLIProvider) async -> [String]? {
        guard provider == .apple else { return nil }
        guard #available(macOS 26.0, *) else { return nil }
        let locales = await SpeechTranscriber.supportedLocales
        return locales.map(\.identifier).sorted()
    }
}
