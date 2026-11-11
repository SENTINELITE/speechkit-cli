import Foundation
import Testing
@testable import SpeechKitCLICore

@Suite("languages command")
struct LanguagesCommandTests {
    @Test("Enumerated providers list their values")
    func enumeratedProviders() throws {
        for provider in [CLIProvider.grok, .aqua, .cohere, .meta] {
            let report = LanguageReport.make(for: provider)
            #expect(report.values == LanguageMapping.validValues(for: provider))
            #expect(!report.values.isEmpty)
            #expect(report.render().contains(report.values[0]))
        }
    }

    @Test("Meta lists the codes its name table accepts")
    func metaValues() {
        let report = LanguageReport.make(for: .meta)
        #expect(report.style == "languageName")
        #expect(report.values.contains("en"))
        #expect(report.values.contains("fil"))
    }

    @Test("OpenAI and Gemini say any code is accepted")
    func freeFormProviders() {
        #expect(LanguageReport.make(for: .openai).note.contains("any BCP-47 or ISO 639-1 code"))
        #expect(LanguageReport.make(for: .openai).values.isEmpty)
        #expect(LanguageReport.make(for: .gemini).note.contains("any BCP-47 code"))
        #expect(LanguageReport.make(for: .gemini).values.isEmpty)
    }

    @Test("ElevenLabs accepts any ISO code but has no fixed list")
    func elevenLabs() {
        let report = LanguageReport.make(for: .elevenlabs)
        #expect(report.note.contains("ISO 639-1 or 639-3"))
        #expect(report.values.isEmpty)
    }

    @Test("Apple lists the locales it was given, or explains why it cannot")
    func apple() {
        let listed = LanguageReport.make(for: .apple, appleLocales: ["en-US", "fr-FR"])
        #expect(listed.values == ["en-US", "fr-FR"])
        #expect(listed.render().contains("en-US"))

        let unavailable = LanguageReport.make(for: .apple, appleLocales: nil)
        #expect(unavailable.values.isEmpty)
        #expect(unavailable.note.contains("macOS 26"))
    }

    @Test("Apple locales are read only for the apple provider")
    func appleLocalesOnlyForApple() async {
        #expect(await Languages.appleLocales(for: .grok) == nil)
    }

    @Test("The report encodes as one object")
    func jsonOutput() throws {
        let data = try JSONEncoder().encode(LanguageReport.make(for: .cohere))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["provider"] as? String == "cohere")
        #expect((decoded?["values"] as? [String])?.isEmpty == false)
    }

    @Test("languages parses a provider and --json")
    func parsing() throws {
        let command = try Languages.parse(["Meta", "--json"])
        #expect(command.provider == .meta)
        #expect(command.json)
        #expect(try Languages.parse(["apple"]).json == false)
        #expect(throws: (any Error).self) { _ = try Languages.parse([]) }
        #expect(throws: (any Error).self) { _ = try Languages.parse(["whisper"]) }
    }
}
