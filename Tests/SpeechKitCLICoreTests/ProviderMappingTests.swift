import Foundation
import SpeechKit
import Testing
@testable import SpeechKitCLICore

@Suite("Provider mapping")
struct ProviderMappingTests {
    private let file = URL(fileURLWithPath: "/tmp/talk.wav")

    @Test("Grok words map into words and sentence segments")
    func grokMapping() throws {
        let response = try Fixture.decode(GrokFileTranscriptionResponse.self, from: "grok-response")
        let document = GrokRunner.map(response, file: file, modelID: .stt)

        #expect(document.provider == "grok")
        #expect(document.model == "grok-stt")
        #expect(document.language == "en")
        #expect(document.duration == 3.25)
        #expect(document.sourceFile == "/tmp/talk.wav")
        #expect(document.words.count == 5)
        #expect(document.words[0] == TranscriptDocument.Word(text: "Hello", start: 0, end: 0.42, speaker: "0"))
        #expect(document.segments.count == 2)
        #expect(document.segments[0].text == "Hello there.")
        #expect(document.segments[0].speaker == "0")
        #expect(document.segments[1].text == "How are you?")
        #expect(document.segments[1].speaker == "1")
        #expect(document.segments[1].start == 1.4)
        #expect(document.warnings.isEmpty)
    }

    @Test("Grok without words falls back to one untimed segment and warns")
    func grokWithoutWords() throws {
        let json = Data(#"{"text":"Hello there.","duration":2.0}"#.utf8)
        let response = try JSONDecoder().decode(GrokFileTranscriptionResponse.self, from: json)
        let document = GrokRunner.map(response, file: file, modelID: .stt)

        #expect(document.words.isEmpty)
        #expect(document.segments == [TranscriptDocument.Segment(start: 0, end: 2, text: "Hello there.")])
        #expect(document.warnings.count == 1)
    }

    @Test("Grok notes that --raw is unavailable")
    func grokRawWarning() throws {
        let response = try Fixture.decode(GrokFileTranscriptionResponse.self, from: "grok-response")
        let document = GrokRunner.map(response, file: file, modelID: .stt, includeRaw: true)
        #expect(document.warnings.contains { $0.contains("--raw") })
    }

    @Test("OpenAI segments and words map through")
    func openAIMapping() throws {
        let response = try Fixture.decode(OpenAIFileTranscriptionResponse.self, from: "openai-response")
        let document = OpenAIRunner.map(response, file: file, modelID: .gptTranscribe)

        #expect(document.provider == "openai")
        #expect(document.model == "gpt-transcribe")
        #expect(document.language == "en")
        #expect(document.segments.count == 2)
        #expect(document.segments[0].text == "Hello there.")
        #expect(document.segments[0].speaker == nil)
        #expect(document.words.count == 2)
        #expect(document.words[1] == TranscriptDocument.Word(text: "there.", start: 0.42, end: 0.95))
        #expect(document.warnings.isEmpty)
    }

    @Test("OpenAI diarized segments carry speakers and the first detected language")
    func openAIDiarizedMapping() throws {
        let response = try Fixture.decode(OpenAIFileTranscriptionResponse.self, from: "openai-diarized-response")
        let document = OpenAIRunner.map(response, file: file, modelID: .gpt4oTranscribeDiarize)

        #expect(document.language == "en")
        #expect(document.segments.map(\.speaker) == ["A", "B"])
        #expect(document.segments[1].end == 2.2)
        #expect(document.words.isEmpty)
    }

    @Test("Capabilities describe every provider")
    func capabilities() {
        for provider in CLIProvider.allCases {
            let capabilities = ProviderCapabilities.capabilities(for: provider)
            #expect(capabilities.requiresMacOS26 == (provider == .apple))
        }
        #expect(ProviderCapabilities.capabilities(for: .cohere).supportsSegments == false)
        #expect(ProviderCapabilities.capabilities(for: .meta).supportsWordTimestamps == false)
        #expect(ProviderCapabilities.capabilities(for: .meta).supportsSegments)
        #expect(ProviderCapabilities.capabilities(for: .apple).maxFileBytes == nil)
        #expect(ProviderCapabilities.capabilities(for: .openai).languageStyle == .iso639)
    }

    @Test("The registry only builds the phase one runners")
    func registry() throws {
        let context = RunContext(credential: .apiKey("key"))
        #expect(try ProviderRegistry.makeRunner(for: .grok, context: context) is GrokRunner)
        #expect(try ProviderRegistry.makeRunner(for: .openai, context: context) is OpenAIRunner)
        #expect(throws: CLIError.notImplemented("--provider gemini")) {
            _ = try ProviderRegistry.makeRunner(for: .gemini, context: context)
        }
    }
}
