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
    /// Gemini takes BCP-47 tags, so codes pass through with the region subtag
    /// intact. Empty entries are dropped so `--language ""` does not reach the API.
    public static func gemini(_ codes: [String]) -> [String] {
        codes
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Language names Meta accepts, keyed by the code callers are likely to pass.
    ///
    /// Meta biases transcription with names such as `Mandarin Chinese`, so the
    /// table covers every ``MetaLanguage`` case plus the aliases that ISO 639
    /// and BCP-47 both allow for the same language.
    static let metaLanguagesByCode: [String: MetaLanguage] = [
        "ar": .arabic,
        "bn": .bengali,
        "nl": .dutch,
        "en": .english,
        "fr": .french,
        "de": .german,
        "he": .hebrew,
        "iw": .hebrew,
        "hi": .hindi,
        "id": .indonesian,
        "in": .indonesian,
        "it": .italian,
        "ja": .japanese,
        "kn": .kannada,
        "ko": .korean,
        "ms": .malay,
        "zh": .mandarinChinese,
        "cmn": .mandarinChinese,
        "mr": .marathi,
        "pl": .polish,
        "pt": .portuguese,
        "es": .spanish,
        "tl": .tagalog,
        "fil": .tagalog,
        "ta": .tamil,
        "te": .telugu,
        "th": .thai,
        "tr": .turkish,
        "vi": .vietnamese
    ]

    /// Returns the Meta language bias for the requested codes.
    ///
    /// Region subtags are ignored, so `zh-CN` and `pt-BR` resolve the same way
    /// as `zh` and `pt`.
    ///
    /// - Throws: ``CLIError/invalidLanguage(provider:code:valid:)`` when a code has no Meta name.
    public static func meta(_ codes: [String]) throws -> [MetaLanguage] {
        try codes.map { code in
            let lowered = code.lowercased()
            if let language = metaLanguagesByCode[lowered] ?? metaLanguagesByCode[baseCode(code)] {
                return language
            }
            throw CLIError.invalidLanguage(
                provider: .meta,
                code: code,
                valid: metaLanguagesByCode.keys.sorted()
            )
        }
    }

    /// Returns the Aqua language for the first requested code.
    ///
    /// - Throws: ``CLIError/invalidLanguage(provider:code:valid:)`` when Aqua has no matching case.
    public static func aqua(_ codes: [String]) throws -> AquaLanguage? {
        guard let code = codes.first, !code.isEmpty else { return nil }
        if let language = AquaLanguage(rawValue: code.lowercased()) {
            return language
        }
        if let language = AquaLanguage(rawValue: baseCode(code)) {
            return language
        }
        throw CLIError.invalidLanguage(
            provider: .aqua,
            code: code,
            valid: AquaLanguage.allCases.map(\.rawValue).sorted()
        )
    }

    /// Returns the Cohere language for the first requested code.
    ///
    /// - Throws: ``CLIError/invalidLanguage(provider:code:valid:)`` when Cohere has no matching case.
    public static func cohere(_ codes: [String]) throws -> CohereLanguage? {
        guard let code = codes.first, !code.isEmpty else { return nil }
        if let language = CohereLanguage(rawValue: code.lowercased()) {
            return language
        }
        if let language = CohereLanguage(rawValue: baseCode(code)) {
            return language
        }
        throw CLIError.invalidLanguage(
            provider: .cohere,
            code: code,
            valid: CohereLanguage.allCases.map(\.rawValue).sorted()
        )
    }

    /// Returns the values a provider accepts for `--language`.
    ///
    /// The result is `nil` when the provider takes any well-formed language
    /// tag, and an empty array when it takes none at all.
    public static func validValues(for provider: CLIProvider) -> [String]? {
        switch provider {
        case .grok:
            return GrokLanguage.allCases.map(\.rawValue).sorted()
        case .aqua:
            return AquaLanguage.allCases.map(\.rawValue).sorted()
        case .cohere:
            return CohereLanguage.allCases.map(\.rawValue).sorted()
        case .meta:
            return metaLanguagesByCode.keys.sorted()
        case .elevenlabs, .voz:
            return []
        case .openai, .gemini, .apple:
            return nil
        }
    }
}
