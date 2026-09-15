import Foundation
import Testing
@testable import SpeechKitCLICore

@Suite("providers command")
struct ProvidersCommandTests {
    private var reports: [ProviderReport] {
        ProviderReport.all(
            environment: ["SPEECHKIT_OPENAI_API_KEY": "sk-env"],
            store: InMemoryKeychainStore(keys: [.grok: "g"])
        )
    }

    @Test("The table renders with fixed-width plain ASCII columns")
    func goldenTable() {
        let table = ProviderReport.table(reports)
        #expect(table == """
        PROVIDER    DEFAULT MODEL              WORDS  SEGMENTS  DIARIZE  LANGUAGE      MAX SIZE  MACOS  CREDENTIAL  EXTENSIONS
        elevenlabs  scribe_v1                  yes    yes       no       none          3 GB      15     none        any
        aqua        avalon-v1.5                no     no        no       providerEnum  25 MB     15     none        flac,m4a,mp3,mp4,mpeg,mpga,ogg,wav,webm
        cohere      cohere-transcribe-03-2026  no     no        no       providerEnum  25 MB     15     none        flac,mp3,mpeg,mpga,ogg,wav
        grok        grok-stt                   yes    yes       yes      providerEnum  500 MB    15     keychain    aac,flac,m4a,mkv,mp3,mp4,ogg,opus,wav
        openai      gpt-transcribe             yes    yes       yes      iso639        25 MB     15     env         m4a,mp3,mp4,mpeg,mpga,wav,webm
        meta        muse-voice-transcribe-1.0  no     yes       yes      languageName  32 MB     15     none        wav
        gemini      gemini-3.5-transcribe      yes    yes       yes      bcp47         -         15     none        aac,aif,aiff,flac,m4a,mp3,mpeg,mpga,ogg,opus,wav,webm
        apple       -                          yes    yes       no       locale        -         26     not needed  any
        voz         voz v0.1.0                 yes    yes       no       none          -         15     not needed  any

        """)
    }

    @Test("Every row reports one provider in --provider order")
    func rowOrder() {
        #expect(reports.map(\.provider) == CLIProvider.allValueStrings)
    }

    @Test("The credential column reports the environment, the keychain, or nothing")
    func credentialSources() {
        let byProvider = Dictionary(uniqueKeysWithValues: reports.map { ($0.provider, $0.credentialSource) })
        #expect(byProvider["openai"] == .environment)
        #expect(byProvider["grok"] == .keychain)
        #expect(byProvider["meta"] == .notFound)
        #expect(byProvider["apple"] == .notNeeded)
        #expect(byProvider["voz"] == .notNeeded)
    }

    @Test("--json emits an array of objects")
    func jsonOutput() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(reports)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        #expect(decoded?.count == CLIProvider.allCases.count)
        let first = try #require(decoded?.first)
        #expect(first["provider"] as? String == "elevenlabs")
        #expect(first["segments"] as? Bool == true)
        #expect(first["credentialSource"] as? String == "none")
        #expect(first["maxFileBytes"] as? Int == 3 * 1024 * 1024 * 1024)
        #expect(first["acceptedExtensions"] == nil)
    }

    @Test("Byte limits print in whole binary units")
    func byteSizes() {
        #expect(ProviderReport.byteSize(25 * 1024 * 1024) == "25 MB")
        #expect(ProviderReport.byteSize(3 * 1024 * 1024 * 1024) == "3 GB")
        #expect(ProviderReport.byteSize(1536) == "1.5 KB")
        #expect(ProviderReport.byteSize(12) == "12 B")
    }

    @Test("providers parses --json")
    func parsing() throws {
        #expect(try Providers.parse([]).json == false)
        #expect(try Providers.parse(["--json"]).json)
    }
}
