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

    @Test("Providers arriving in later phases refuse language input")
    func laterPhases() throws {
        #expect(throws: CLIError.notImplemented("--language for gemini")) {
            _ = try LanguageMapping.gemini(["en"])
        }
        #expect(throws: CLIError.notImplemented("--language for meta")) {
            _ = try LanguageMapping.meta(["en"])
        }
        #expect(throws: CLIError.notImplemented("--language for aqua")) {
            _ = try LanguageMapping.aqua(["en"])
        }
        #expect(throws: CLIError.notImplemented("--language for cohere")) {
            _ = try LanguageMapping.cohere(["en"])
        }
        #expect(throws: CLIError.self) {
            try LanguageMapping.elevenLabs(["en"])
        }
        #expect(try LanguageMapping.gemini([]) == [])
    }
}
