import Foundation
import SpeechKit

/// Maps `--language` values onto what each provider accepts.
public enum LanguageMapping {
    /// Returns the lowercased two-letter base of a language tag.
    ///
    /// `en-US` and `en_US` both return `en`. Three-letter subtags such as
    /// `fil` are returned whole, because some providers use them as codes.
    public static func baseCode(_ code: String) -> String {
        let separators = CharacterSet(charactersIn: "-_")
        let first = code.components(separatedBy: separators).first ?? code
        return first.lowercased()
    }

    /// Returns the Grok language for the first requested code.
    ///
    /// - Throws: ``CLIError/invalidLanguage(provider:code:valid:)`` when Grok has no matching case.
    public static func grok(_ codes: [String]) throws -> GrokLanguage? {
        guard let code = codes.first else { return nil }
        let base = baseCode(code)
        if let language = GrokLanguage(rawValue: base) {
            return language
        }
        // Grok spells Filipino `fil`, which is not a two-letter base code.
        if let language = GrokLanguage(rawValue: code.lowercased()) {
            return language
        }
        throw CLIError.invalidLanguage(
            provider: .grok,
            code: code,
            valid: GrokLanguage.allCases.map(\.rawValue).sorted()
        )
    }

    /// Returns the OpenAI language values for the requested codes.
    ///
    /// OpenAI takes ISO 639-1 strings, so codes pass through unchanged. The
    /// first code fills `language` and every code fills `languages`.
    public static func openAI(_ codes: [String]) -> (language: String?, languages: [String]) {
        let normalized = codes.map { $0.lowercased() }
        return (normalized.first, normalized)
    }

    /// Returns the Apple locale for the first requested code.
    public static func apple(_ codes: [String]) -> Locale? {
        guard let code = codes.first, !code.isEmpty else { return nil }
        return Locale(identifier: code)
    }

    /// Returns the Gemini language codes for the requested codes.
    ///
    /// - Throws: ``CLIError/notImplemented(_:)`` until the Gemini runner lands.
    public static func gemini(_ codes: [String]) throws -> [String] {
        guard codes.isEmpty else {
            throw CLIError.notImplemented("--language for gemini")
        }
        return []
    }

    /// Returns the Meta language for the first requested code.
    ///
    /// - Throws: ``CLIError/notImplemented(_:)`` until the Meta code-to-name table lands.
    public static func meta(_ codes: [String]) throws -> String? {
        guard codes.isEmpty else {
            throw CLIError.notImplemented("--language for meta")
        }
        return nil
    }

    /// Returns the Aqua language code for the first requested code.
    ///
    /// - Throws: ``CLIError/notImplemented(_:)`` until the Aqua runner lands.
    public static func aqua(_ codes: [String]) throws -> String? {
        guard codes.isEmpty else {
            throw CLIError.notImplemented("--language for aqua")
        }
        return nil
    }

    /// Returns the Cohere language code for the first requested code.
    ///
    /// - Throws: ``CLIError/notImplemented(_:)`` until the Cohere runner lands.
    public static func cohere(_ codes: [String]) throws -> String? {
        guard codes.isEmpty else {
            throw CLIError.notImplemented("--language for cohere")
        }
        return nil
    }

    /// Reports that ElevenLabs Scribe detects the language itself.
    ///
    /// - Throws: ``CLIError/invalidLanguage(provider:code:valid:)`` when a code is given.
    public static func elevenLabs(_ codes: [String]) throws {
        guard codes.isEmpty else {
            throw CLIError.invalidLanguage(provider: .elevenlabs, code: codes[0], valid: [])
        }
    }
}
