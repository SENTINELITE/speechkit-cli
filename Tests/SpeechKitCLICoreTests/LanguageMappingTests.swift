import Foundation
import SpeechKit
import Testing
@testable import SpeechKitCLICore

@Suite("Language mapping")
struct LanguageMappingTests {
    @Test("Base codes drop the region subtag")
    func baseCodes() {
        #expect(LanguageMapping.baseCode("en-US") == "en")
        #expect(LanguageMapping.baseCode("pt_BR") == "pt")
        #expect(LanguageMapping.baseCode("EN") == "en")
    }

    @Test("Grok maps the two-letter base code")
    func grok() throws {
        #expect(try LanguageMapping.grok(["en-US"]) == .english)
        #expect(try LanguageMapping.grok(["pt-BR"]) == .portuguese)
        #expect(try LanguageMapping.grok(["fil"]) == .filipino)
        #expect(try LanguageMapping.grok([]) == nil)
    }

    @Test("Grok reports the valid list for an unknown code")
    func grokInvalid() {
        #expect(throws: CLIError.self) {
            _ = try LanguageMapping.grok(["xx"])
        }
        do {
            _ = try LanguageMapping.grok(["xx"])
            Issue.record("expected a thrown error")
        } catch let error as CLIError {
            #expect(error.localizedDescription.contains("en"))
            #expect(error.exitCode == 1)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("OpenAI passes codes through")
    func openAI() {
        let mapped = LanguageMapping.openAI(["EN", "fr"])
        #expect(mapped.language == "en")
        #expect(mapped.languages == ["en", "fr"])
        #expect(LanguageMapping.openAI([]).language == nil)
    }

    @Test("Apple builds a locale")
    func apple() {
        #expect(LanguageMapping.apple(["en-US"])?.identifier == "en-US")
        #expect(LanguageMapping.apple([]) == nil)
    }

    @Test("Gemini passes BCP-47 tags through and drops empty entries")
    func gemini() {
        #expect(LanguageMapping.gemini(["en-US", "fr-FR"]) == ["en-US", "fr-FR"])
        #expect(LanguageMapping.gemini(["", "  "]) == [])
        #expect(LanguageMapping.gemini([]) == [])
    }

    @Test("Meta maps every language name in the enum")
    func metaCoversEveryCase() throws {
        let mapped = Set(LanguageMapping.metaLanguagesByCode.values)
        #expect(mapped.count == MetaLanguage.allCases.count)
        for language in MetaLanguage.allCases {
            #expect(mapped.contains(language), "no code maps to \(language.rawValue)")
        }
    }

    @Test("Meta accepts aliases and region subtags")
    func metaAliases() throws {
        #expect(try LanguageMapping.meta(["en"]) == [.english])
        #expect(try LanguageMapping.meta(["en-GB"]) == [.english])
        #expect(try LanguageMapping.meta(["zh"]) == [.mandarinChinese])
        #expect(try LanguageMapping.meta(["cmn"]) == [.mandarinChinese])
        #expect(try LanguageMapping.meta(["zh-CN"]) == [.mandarinChinese])
        #expect(try LanguageMapping.meta(["tl"]) == [.tagalog])
        #expect(try LanguageMapping.meta(["fil"]) == [.tagalog])
        #expect(try LanguageMapping.meta(["id"]) == [.indonesian])
        #expect(try LanguageMapping.meta(["in"]) == [.indonesian])
        #expect(try LanguageMapping.meta(["ms"]) == [.malay])
        #expect(try LanguageMapping.meta(["pt"]) == [.portuguese])
        #expect(try LanguageMapping.meta(["pt-BR"]) == [.portuguese])
        #expect(try LanguageMapping.meta(["iw"]) == [.hebrew])
        #expect(try LanguageMapping.meta(["en", "fr"]) == [.english, .french])
        #expect(try LanguageMapping.meta([]).isEmpty)
    }

    @Test("Meta reports the valid codes for an unmapped language")
    func metaInvalid() {
        do {
            _ = try LanguageMapping.meta(["xx"])
            Issue.record("expected a thrown error")
        } catch let error as CLIError {
            #expect(error.localizedDescription.contains("zh"))
            #expect(error.localizedDescription.contains("fil"))
            #expect(error.exitCode == 1)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("Aqua takes raw values and falls back to the base code")
    func aqua() throws {
        #expect(try LanguageMapping.aqua(["en"]) == .english)
        #expect(try LanguageMapping.aqua(["en-US"]) == .english)
        #expect(try LanguageMapping.aqua(["auto"]) == .auto)
        #expect(try LanguageMapping.aqua([]) == nil)
        do {
            _ = try LanguageMapping.aqua(["pt"])
            Issue.record("expected a thrown error")
        } catch let error as CLIError {
            #expect(error.localizedDescription.contains("ja"))
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("Cohere takes raw values and falls back to the base code")
    func cohere() throws {
        #expect(try LanguageMapping.cohere(["pt-BR"]) == .portuguese)
        #expect(try LanguageMapping.cohere(["ZH"]) == .chinese)
        #expect(try LanguageMapping.cohere([]) == nil)
        do {
            _ = try LanguageMapping.cohere(["sv"])
            Issue.record("expected a thrown error")
        } catch let error as CLIError {
            #expect(error.localizedDescription.contains("ko"))
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("ElevenLabs takes no language at all, so it lists no values")
    func elevenLabs() {
        #expect(LanguageMapping.validValues(for: .elevenlabs) == [])
    }

    @Test("Valid values are listed for enumerated providers and nil for free-form ones")
    func validValues() {
        #expect(LanguageMapping.validValues(for: .grok)?.contains("en") == true)
        #expect(LanguageMapping.validValues(for: .aqua) == AquaLanguage.allCases.map(\.rawValue).sorted())
        #expect(LanguageMapping.validValues(for: .cohere)?.count == CohereLanguage.allCases.count)
        #expect(LanguageMapping.validValues(for: .meta)?.contains("cmn") == true)
        #expect(LanguageMapping.validValues(for: .elevenlabs) == [])
        #expect(LanguageMapping.validValues(for: .openai) == nil)
        #expect(LanguageMapping.validValues(for: .gemini) == nil)
        #expect(LanguageMapping.validValues(for: .apple) == nil)
    }
}
