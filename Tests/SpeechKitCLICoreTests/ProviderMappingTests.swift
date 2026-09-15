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
        #expect(ProviderCapabilities.capabilities(for: .meta).acceptedExtensions == ["wav"])
        #expect(ProviderCapabilities.capabilities(for: .cohere).acceptedExtensions?.contains("mp4") == false)
        #expect(ProviderCapabilities.capabilities(for: .aqua).acceptedExtensions?.contains("m4a") == true)
        #expect(ProviderCapabilities.capabilities(for: .elevenlabs).acceptedExtensions == nil)
        #expect(ProviderCapabilities.capabilities(for: .gemini).maxFileBytes == nil)
    }

    @Test("Gemini words carry speakers and the first detected language")
    func geminiMapping() throws {
        let response = try Fixture.decode(GeminiFileTranscriptionResponse.self, from: "gemini-response")
        let document = GeminiRunner.map(response, file: file, modelID: .transcribe35)

        #expect(document.provider == "gemini")
        #expect(document.model == "gemini-3.5-transcribe")
        #expect(document.language == "en-US")
        #expect(document.text == "Hello there. How are you?")
        #expect(document.duration == 2.2)
        #expect(document.words.count == 5)
        #expect(document.words[0] == TranscriptDocument.Word(text: "Hello", start: 0, end: 0.42, speaker: "A"))
        #expect(document.segments.count == 2)
        #expect(document.segments[0].text == "Hello there.")
        #expect(document.segments[0].speaker == "A")
        #expect(document.segments[1].speaker == "B")
        #expect(document.segments[1].end == 2.2)
        #expect(document.warnings.isEmpty)
    }

    @Test("Gemini words without an end time keep their start")
    func geminiPartialWords() throws {
        let response = try Fixture.decode(GeminiFileTranscriptionResponse.self, from: "gemini-partial-words")
        let document = GeminiRunner.map(response, file: file, modelID: .transcribe35)

        #expect(document.language == nil)
        #expect(document.words.count == 2)
        #expect(document.words[1].start == 0.42)
        #expect(document.words[1].end == nil)
        #expect(document.words[1].speaker == nil)
        #expect(document.segments.count == 1)
        #expect(document.segments[0].text == "Hello there.")
        #expect(document.segments[0].start == 0)
        // The cue builder closes a word with no end time itself.
        #expect(document.segments[0].end >= 0.42)
    }

    @Test("Gemini without words falls back to one untimed segment and warns")
    func geminiWithoutWords() {
        let response = GeminiFileTranscriptionResponse(id: "1", status: "completed", text: "Hello there.")
        let document = GeminiRunner.map(response, file: file, modelID: .transcribe35)

        #expect(document.words.isEmpty)
        #expect(document.duration == nil)
        #expect(document.segments == [TranscriptDocument.Segment(start: 0, end: 0, text: "Hello there.")])
        #expect(document.warnings.count == 1)
    }

    @Test("Meta turns become segments in seconds with speakers")
    func metaMapping() throws {
        let response = try Fixture.decode(MetaFileTranscriptionResponse.self, from: "meta-response")
        let document = MetaRunner.map(response, file: file, modelID: .museVoiceTranscribe1)

        #expect(document.provider == "meta")
        #expect(document.model == "muse-voice-transcribe-1.0")
        #expect(document.language == nil)
        #expect(document.duration == 3.25)
        #expect(document.words.isEmpty)
        #expect(document.segments.count == 2)
        #expect(document.segments[0] == TranscriptDocument.Segment(
            start: 0,
            end: 0.95,
            text: "Hello there.",
            speaker: "speaker_0"
        ))
        #expect(document.segments[1].start == 1.4)
        #expect(document.segments[1].speaker == "speaker_1")
        #expect(document.warnings.isEmpty)
    }

    @Test("Meta without turns falls back to one untimed segment and warns")
    func metaWithoutTurns() throws {
        let response = try Fixture.decode(MetaFileTranscriptionResponse.self, from: "meta-no-turns")
        let document = MetaRunner.map(response, file: file, modelID: .museVoiceTranscribe1)

        #expect(document.segments == [TranscriptDocument.Segment(start: 0, end: 2, text: "Hello there.")])
        #expect(document.warnings.count == 1)
    }

    @Test("Meta carries forward warnings for dropped options")
    func metaWarnings() throws {
        let response = try Fixture.decode(MetaFileTranscriptionResponse.self, from: "meta-response")
        let document = MetaRunner.map(
            response,
            file: file,
            modelID: .museVoiceTranscribe1,
            warnings: ["Meta has no prompt parameter; --prompt was dropped."]
        )
        #expect(document.warnings.count == 1)
    }

    @Test("ElevenLabs spacing tokens stay out of words and segments")
    func elevenLabsMapping() throws {
        let response = try Fixture.decode(ElevenLabsFileTranscriptionResponse.self, from: "elevenlabs-response")
        let document = ElevenLabsRunner.map(response, file: file, modelID: .scribeV1)

        #expect(document.provider == "elevenlabs")
        #expect(document.model == "scribe_v1")
        #expect(document.language == "eng")
        #expect(document.duration == 2.2)
        #expect(document.words.count == 5)
        #expect(document.words.allSatisfy { $0.text.trimmingCharacters(in: .whitespaces) == $0.text })
        #expect(document.words[0] == TranscriptDocument.Word(
            text: "Hello",
            start: 0,
            end: 0.42,
            confidence: -0.12
        ))
        let segmentText = document.segments.map(\.text).joined(separator: " ")
        #expect(segmentText == "Hello there. How are you?")
        #expect(document.segments.allSatisfy { !$0.text.contains("  ") })
        #expect(document.segments.first?.start == 0)
        #expect(document.segments.last?.end == 2.2)
        #expect(document.warnings.isEmpty)
    }

    @Test("ElevenLabs notes that --language is ignored")
    func elevenLabsLanguageWarning() throws {
        let response = try Fixture.decode(ElevenLabsFileTranscriptionResponse.self, from: "elevenlabs-response")
        let document = ElevenLabsRunner.map(
            response,
            file: file,
            modelID: .scribeV2,
            warnings: ["ElevenLabs Scribe detects the language itself; --language was ignored."]
        )
        #expect(document.model == "scribe_v2")
        #expect(document.warnings.count == 1)
        #expect(document.warnings[0].contains("--language"))
    }

    @Test("Aqua returns one untimed segment and no words")
    func aquaMapping() throws {
        let response = try Fixture.decode(AquaFileTranscriptionResponse.self, from: "aqua-response")
        let document = AquaRunner.map(response, file: file, modelID: .avalonV15)

        #expect(document.provider == "aqua")
        #expect(document.model == "avalon-v1.5")
        #expect(document.language == nil)
        #expect(document.duration == nil)
        #expect(document.words.isEmpty)
        #expect(document.segments == [
            TranscriptDocument.Segment(start: 0, end: 0, text: "Hello there. How are you?")
        ])
        #expect(document.hasTimings == false)
        #expect(document.warnings.count == 1)
    }

    @Test("Cohere returns one untimed segment and no words")
    func cohereMapping() {
        let document = CohereRunner.map("Hello there. How are you?", file: file, modelID: .transcribe032026)

        #expect(document.provider == "cohere")
        #expect(document.model == "cohere-transcribe-03-2026")
        #expect(document.language == nil)
        #expect(document.words.isEmpty)
        #expect(document.segments.count == 1)
        #expect(document.segments[0].text == "Hello there. How are you?")
        #expect(document.hasTimings == false)
        #expect(document.warnings.count == 1)
    }

    @Test("The registry builds a runner for every provider")
    func registry() async throws {
        let context = RunContext(credential: .apiKey("key"))
        #expect(try await ProviderRegistry.makeRunner(for: .grok, context: context) is GrokRunner)
        #expect(try await ProviderRegistry.makeRunner(for: .openai, context: context) is OpenAIRunner)
        #expect(try await ProviderRegistry.makeRunner(for: .gemini, context: context) is GeminiRunner)
        #expect(try await ProviderRegistry.makeRunner(for: .meta, context: context) is MetaRunner)
        #expect(try await ProviderRegistry.makeRunner(for: .elevenlabs, context: context) is ElevenLabsRunner)
        #expect(try await ProviderRegistry.makeRunner(for: .aqua, context: context) is AquaRunner)
        #expect(try await ProviderRegistry.makeRunner(for: .cohere, context: context) is CohereRunner)
    }

    @Test("The registry rejects a bad language before any upload")
    func registryValidatesLanguage() async {
        let context = RunContext(credential: .apiKey("key"), languages: ["xx"])
        do {
            _ = try await ProviderRegistry.makeRunner(for: .meta, context: context)
            Issue.record("expected a thrown error")
        } catch let error as CLIError {
            #expect(error.exitCode == 1)
            #expect(error.localizedDescription.contains("zh"))
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("Every provider rejects a bad model with exit code 1 before any upload")
    func registryValidatesModel() async throws {
        let bad = ["elevenlabs": "scribe_v2_realtime"]
        // Apple has no model identifier at all, so it notes that --model was
        // ignored rather than refusing the run.
        for provider in CLIProvider.allCases where provider != .apple {
            let context = RunContext(credential: .apiKey("key"), model: bad[provider.rawValue] ?? "bogus")
            do {
                _ = try await ProviderRegistry.makeRunner(for: provider, context: context)
                Issue.record("\(provider.rawValue) accepted a bogus model")
            } catch let error as CLIError {
                #expect(error.exitCode == 1)
            } catch {
                Issue.record("unexpected error \(error)")
            }
        }
    }

    @Test("Grok notes the options it has to drop")
    func grokDroppedOptions() throws {
        let warnings = RunnerSupport.droppedOptionWarnings(
            prompt: "a hint",
            keywords: ["SpeechKit"],
            for: .grok
        )
        #expect(warnings == [
            "Grok has no prompt parameter; --prompt was dropped.",
            "Grok has no vocabulary parameter; --keyword was dropped.",
        ])

        let response = try Fixture.decode(GrokFileTranscriptionResponse.self, from: "grok-response")
        let document = GrokRunner.map(response, file: file, modelID: .stt, warnings: warnings)
        #expect(document.warnings == warnings)
    }

    @Test("--max-cue-chars reaches Gemini and ElevenLabs segment building")
    func cueLimitsReachRunners() throws {
        // Six characters is narrower than any two of the fixture's words, so
        // every cue the builder produces holds one word.
        let tight = CueBuilder(maxCueDuration: 7, maxCueChars: 6)

        let gemini = try Fixture.decode(GeminiFileTranscriptionResponse.self, from: "gemini-response")
        let wide = GeminiRunner.map(gemini, file: file, modelID: .transcribe35)
        let narrow = GeminiRunner.map(gemini, file: file, modelID: .transcribe35, cueBuilder: tight)
        #expect(narrow.segments.count > wide.segments.count)
        #expect(narrow.segments.count == narrow.words.count)

        let scribe = try Fixture.decode(ElevenLabsFileTranscriptionResponse.self, from: "elevenlabs-response")
        let wideScribe = ElevenLabsRunner.map(scribe, file: file, modelID: .scribeV1)
        let narrowScribe = ElevenLabsRunner.map(scribe, file: file, modelID: .scribeV1, cueBuilder: tight)
        #expect(narrowScribe.segments.count > wideScribe.segments.count)
        #expect(narrowScribe.segments.count == narrowScribe.words.count)
    }
}
