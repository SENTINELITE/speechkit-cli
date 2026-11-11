import ArgumentParser
import Foundation
import SpeechKit
import Testing
@testable import SpeechKitCLICore

@Suite("ElevenLabs")
struct ElevenLabsRunnerTests {
    private let file = URL(fileURLWithPath: "/tmp/talk.wav")

    // MARK: Parsing

    @Test("The ElevenLabs flags parse")
    func flagParsing() throws {
        let command = try Transcribe.parse([
            "a.wav", "-p", "elevenlabs",
            "--diarize", "--speakers", "4",
            "--numbers", "digits",
            "--secondary-language", "fr", "--secondary-language", "de",
            "--keyword", "SpeechKit",
            "--tag-audio-events", "--no-verbatim",
            "--language", "en-US"
        ])
        #expect(command.transcription.diarize)
        #expect(command.transcription.speakers == 4)
        #expect(command.transcription.numbers == .digits)
        #expect(command.transcription.secondaryLanguage == ["fr", "de"])
        #expect(command.transcription.keyword == ["SpeechKit"])
        #expect(command.transcription.tagAudioEvents)
        #expect(command.transcription.noVerbatim)
        #expect(command.transcription.language == ["en-US"])

        let words = try Transcribe.parse(["a.wav", "-p", "elevenlabs", "--numbers", "words"])
        #expect(words.transcription.numbers == .words)
        #expect(throws: (any Error).self) {
            _ = try Transcribe.parse(["a.wav", "-p", "elevenlabs", "--numbers", "roman"])
        }
    }

    @Test("--help lists the ElevenLabs flags")
    func helpListsFlags() {
        let help = Transcribe.helpMessage()
        for flag in ["--speakers", "--numbers", "--secondary-language", "--tag-audio-events", "--no-verbatim"] {
            #expect(help.contains(flag), "help is missing \(flag)")
        }
    }

    // MARK: Capabilities and models

    @Test("fileModelIDs offers the Scribe v3, v2, and v2 Medical models, v3 first")
    func fileModelIDs() {
        #expect(ElevenLabsRunner.fileModelIDs == [.scribeV3, .scribeV2, .scribeV2Medical])
        let capabilities = ProviderCapabilities.capabilities(for: .elevenlabs)
        #expect(capabilities.defaultFileModel == "scribe_v3")
        #expect(capabilities.supportsDiarization)
        #expect(capabilities.languageStyle == .iso639)
        #expect(capabilities.maxFileBytes == Int64(5) * 1024 * 1024 * 1024)
    }

    @Test("Scribe v1 is no longer a valid --model")
    func scribeV1Rejected() async {
        let context = RunContext(credential: .apiKey("key"), model: "scribe_v1")
        do {
            _ = try await ProviderRegistry.makeRunner(for: .elevenlabs, context: context)
            Issue.record("expected a thrown error")
        } catch let error as CLIError {
            #expect(error.exitCode == 1)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    // MARK: Flag validation

    @Test("The ElevenLabs flags are usage errors on every other provider")
    func flagsRejectedElsewhere() async throws {
        let variants: [ElevenLabsRequestOptions] = [
            ElevenLabsRequestOptions(speakerCount: 2),
            ElevenLabsRequestOptions(numbersFormat: .digits),
            ElevenLabsRequestOptions(secondaryLanguages: ["fr"]),
            ElevenLabsRequestOptions(tagAudioEvents: true),
            ElevenLabsRequestOptions(noVerbatim: true)
        ]
        for options in variants {
            let flag = try #require(options.firstSetFlag)
            let context = RunContext(credential: .apiKey("key"), elevenLabs: options)
            do {
                _ = try await ProviderRegistry.makeRunner(for: .grok, context: context)
                Issue.record("grok accepted \(flag)")
            } catch let error as CLIError {
                #expect(error.exitCode == 1)
                #expect(error.localizedDescription.contains(flag))
            } catch {
                Issue.record("unexpected error \(error)")
            }
        }
        #expect(ElevenLabsRequestOptions().firstSetFlag == nil)
    }

    @Test("--speakers needs --diarize and stays inside 1-32")
    func speakerValidation() async {
        let noDiarize = RunContext(
            credential: .apiKey("key"),
            elevenLabs: ElevenLabsRequestOptions(speakerCount: 2)
        )
        await #expect(throws: CLIError.self) {
            try await ElevenLabsRunner(context: noDiarize).validate()
        }
        for count in [0, 33] {
            let context = RunContext(
                credential: .apiKey("key"),
                wantsDiarization: true,
                elevenLabs: ElevenLabsRequestOptions(speakerCount: count)
            )
            await #expect(throws: CLIError.self) {
                try await ElevenLabsRunner(context: context).validate()
            }
        }
        let valid = RunContext(
            credential: .apiKey("key"),
            wantsDiarization: true,
            elevenLabs: ElevenLabsRequestOptions(speakerCount: 2)
        )
        await #expect(throws: Never.self) {
            try await ElevenLabsRunner(context: valid).validate()
        }
    }

    @Test("--numbers and --secondary-language need scribe_v3")
    func v3OnlyFlags() async {
        for options in [
            ElevenLabsRequestOptions(numbersFormat: .words),
            ElevenLabsRequestOptions(secondaryLanguages: ["fr"])
        ] {
            let context = RunContext(
                credential: .apiKey("key"),
                model: "scribe_v2",
                elevenLabs: options
            )
            let error = await #expect(throws: CLIError.self) {
                try await ElevenLabsRunner(context: context).validate()
            }
            #expect(error?.localizedDescription.contains("scribe_v3") == true)
        }
        let medical = RunContext(
            credential: .apiKey("key"),
            model: "scribe_v2_medical",
            elevenLabs: ElevenLabsRequestOptions(numbersFormat: .digits)
        )
        await #expect(throws: CLIError.self) {
            try await ElevenLabsRunner(context: medical).validate()
        }
    }

    @Test("A bad --language or --secondary-language fails before any upload")
    func languageValidation() async {
        let badLanguage = RunContext(credential: .apiKey("key"), languages: ["english"])
        await #expect(throws: CLIError.self) {
            try await ElevenLabsRunner(context: badLanguage).validate()
        }
        let badSecondary = RunContext(
            credential: .apiKey("key"),
            elevenLabs: ElevenLabsRequestOptions(secondaryLanguages: ["x1"])
        )
        await #expect(throws: CLIError.self) {
            try await ElevenLabsRunner(context: badSecondary).validate()
        }
    }

    // MARK: Request options

    @Test("The flags map onto the file transcription options")
    func optionsBuilding() {
        let options = ElevenLabsRunner.options(
            modelID: .scribeV3,
            language: "en",
            request: ElevenLabsRequestOptions(
                speakerCount: 3,
                numbersFormat: .words,
                secondaryLanguages: ["fr", "de"],
                tagAudioEvents: true,
                noVerbatim: true
            ),
            keyterms: ["SpeechKit", "Kirkland"],
            wantsDiarization: true,
            timeout: 30
        )
        #expect(options.modelID == .scribeV3)
        #expect(options.language == "en")
        #expect(options.secondaryLanguages == ["fr", "de"])
        #expect(options.numbersFormat == .words)
        #expect(options.diarize)
        #expect(options.speakerCount == 3)
        #expect(options.keyterms == ["SpeechKit", "Kirkland"])
        #expect(options.tagAudioEvents)
        #expect(options.noVerbatim)
        #expect(options.timeoutInterval == 30)
    }

    @Test("Defaults leave every optional field unset")
    func optionsDefaults() {
        let options = ElevenLabsRunner.options(
            modelID: .scribeV2,
            language: nil,
            request: ElevenLabsRequestOptions(),
            keyterms: [],
            wantsDiarization: false,
            timeout: nil
        )
        #expect(options.language == nil)
        #expect(options.secondaryLanguages.isEmpty)
        #expect(options.numbersFormat == nil)
        #expect(options.diarize == false)
        #expect(options.speakerCount == nil)
        #expect(options.keyterms.isEmpty)
        #expect(options.tagAudioEvents == false)
        #expect(options.noVerbatim == false)
        #expect(options.timeoutInterval == ElevenLabsRunner.defaultTimeout)
    }

    // MARK: Mapping

    @Test("Speaker ids reach the words, and audio events keep no times")
    func speakerMapping() throws {
        let response = try Fixture.decode(ElevenLabsFileTranscriptionResponse.self, from: "elevenlabs-v3-response")
        let document = ElevenLabsRunner.map(response, file: file, modelID: .scribeV3)

        #expect(document.model == "scribe_v3")
        #expect(document.language == "en")
        // The duration comes from audio_duration_secs, not the last word end.
        #expect(document.duration == 3.4)
        #expect(document.words.count == 6)
        #expect(document.words[0].speaker == "speaker_0")
        #expect(document.words.last?.speaker == "speaker_1")
        // The audio event survives as a word with no timestamps.
        let event = try #require(document.words.first { $0.text == "(laughter)" })
        #expect(event.start == nil)
        #expect(event.end == nil)
        #expect(event.speaker == nil)
        // The speaker change splits the segments.
        #expect(document.segments.contains { $0.speaker == "speaker_0" })
        #expect(document.segments.contains { $0.speaker == "speaker_1" })
    }
}
