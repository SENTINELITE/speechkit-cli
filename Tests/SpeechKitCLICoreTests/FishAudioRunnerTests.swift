import ArgumentParser
import Foundation
import SpeechKit
import Testing
@testable import SpeechKitCLICore

@Suite("Fish Audio")
struct FishAudioRunnerTests {
    private let file = URL(fileURLWithPath: "/tmp/talk.wav")

    // MARK: Parsing

    @Test("fish-audio and its alias fish both select Fish Audio")
    func providerParsing() throws {
        #expect(CLIProvider(argument: "fish-audio") == .fishAudio)
        #expect(CLIProvider(argument: "Fish-Audio") == .fishAudio)
        #expect(CLIProvider(argument: "fish") == .fishAudio)
        #expect(CLIProvider(argument: "FISH") == .fishAudio)
        #expect(CLIProvider(argument: "fishaudio") == nil)
        #expect(CLIProvider.fishAudio.rawValue == "fish-audio")
        #expect(CLIProvider.fishAudio.displayName == "Fish Audio")
        #expect(CLIProvider.fishAudio.speechKitProvider == .fishAudio)
        #expect(CLIProvider.fishAudio.requiresCredential)
        #expect(CLIProvider.allValueStrings.contains("fish-audio"))
        // The alias is accepted but never advertised.
        #expect(!CLIProvider.allValueStrings.contains("fish"))

        #expect(try Transcribe.parse(["a.wav", "-p", "fish-audio"]).provider == .fishAudio)
        #expect(try Transcribe.parse(["a.wav", "--provider", "fish"]).provider == .fishAudio)
        #expect(BenchProviderSelection(argument: "fish") == .one(.fishAudio))
        #expect(try CredentialCheck.providers(named: ["fish"]) == [.fishAudio])
    }

    @Test("--help lists fish-audio")
    func helpListsProvider() {
        let help = Transcribe.helpMessage()
        #expect(help.contains("fish-audio"))
    }

    // MARK: Capabilities

    @Test("Capabilities: words, segments, diarization, and an ISO 639-1 hint")
    func capabilities() {
        let capabilities = ProviderCapabilities.capabilities(for: .fishAudio)
        #expect(capabilities.defaultFileModel == "transcribe-1-pro")
        #expect(capabilities.supportsWordTimestamps)
        #expect(capabilities.supportsSegments)
        #expect(capabilities.supportsDiarization)
        #expect(capabilities.languageStyle == .iso639)
        #expect(capabilities.maxFileBytes == nil)
        #expect(capabilities.requiresMacOS26 == false)
        #expect(capabilities.acceptedExtensions?.contains("mp3") == true)
        #expect(capabilities.acceptedExtensions?.contains("m4a") == true)
        #expect(capabilities.acceptedExtensions?.contains("aiff") == false)
        #expect(capabilities.acceptedExtensions?.contains("caf") == false)
    }

    @Test("Dropped options: --prompt and --keyword, but not --timeout")
    func droppedOptions() {
        let warnings = RunnerSupport.droppedOptionWarnings(
            prompt: "a hint",
            keywords: ["SpeechKit"],
            for: .fishAudio
        )
        #expect(warnings == [
            "Fish Audio has no prompt parameter; --prompt was dropped.",
            "Fish Audio has no vocabulary parameter; --keyword was dropped.",
        ])
    }

    @Test("Request options always ask for timestamps and map --diarize")
    func requestOptions() {
        let plain = FishAudioRunner.options(modelID: .transcribe1Pro, language: nil, wantsDiarization: false, timeout: nil)
        #expect(plain.modelID == .transcribe1Pro)
        #expect(plain.timestamps)
        #expect(plain.diarize == .auto)
        #expect(plain.speakerCount == nil)
        #expect(plain.tagAudioEvents)
        #expect(plain.timeoutInterval == 15 * 60)

        let diarized = FishAudioRunner.options(modelID: .transcribe1Pro, language: "en", wantsDiarization: true, timeout: 30)
        #expect(diarized.diarize == .on)
        #expect(diarized.language == "en")
        #expect(diarized.timeoutInterval == 30)
    }

    // MARK: Language

    @Test("--language sends the two-letter base of the first code")
    func languageMapping() throws {
        #expect(try LanguageMapping.fishAudio([]) == nil)
        #expect(try LanguageMapping.fishAudio(["en"]) == "en")
        #expect(try LanguageMapping.fishAudio(["EN-us"]) == "en")
        #expect(try LanguageMapping.fishAudio(["pt_BR", "es"]) == "pt")
        #expect(throws: CLIError.self) { _ = try LanguageMapping.fishAudio(["eng"]) }
        #expect(throws: CLIError.self) { _ = try LanguageMapping.fishAudio(["fil"]) }
        #expect(LanguageMapping.validValues(for: .fishAudio) == nil)
    }

    @Test("The registry builds a Fish Audio runner and rejects a bad language or model")
    func registry() async throws {
        let context = RunContext(credential: .apiKey("key"), languages: ["en-GB"])
        #expect(try await ProviderRegistry.makeRunner(for: .fishAudio, context: context) is FishAudioRunner)

        let badLanguage = RunContext(credential: .apiKey("key"), languages: ["english"])
        await #expect(throws: CLIError.self) {
            _ = try await ProviderRegistry.makeRunner(for: .fishAudio, context: badLanguage)
        }

        let badModel = RunContext(credential: .apiKey("key"), model: "transcribe-1")
        do {
            _ = try await ProviderRegistry.makeRunner(for: .fishAudio, context: badModel)
            Issue.record("expected a thrown error")
        } catch let error as CLIError {
            #expect(error.exitCode == 1)
            #expect(error.localizedDescription.contains("transcribe-1-pro"))
        }
    }

    @Test("languages describes the Fish Audio hint")
    func languagesReport() {
        let report = LanguageReport.make(for: .fishAudio)
        #expect(report.provider == "fish-audio")
        #expect(report.style == "iso639")
        #expect(report.values.isEmpty)
        #expect(report.note.contains("ISO 639-1"))
    }

    // MARK: Mapping

    @Test("Words, speaker turns, text, language, and duration map through")
    func mapping() throws {
        let response = try Fixture.decode(FishAudioFileTranscriptionResponse.self, from: "fish-audio-response")
        let document = FishAudioRunner.map(response, file: file, modelID: .transcribe1Pro)

        #expect(document.provider == "fish-audio")
        #expect(document.model == "transcribe-1-pro")
        #expect(document.sourceFile == "/tmp/talk.wav")
        #expect(document.text == "Hello there. How are you?")
        #expect(document.language == "en")
        #expect(document.duration == 3.25)
        #expect(document.words.map(\.text) == ["Hello", "there.", "How", "are", "you?"])
        #expect(document.words[0] == TranscriptDocument.Word(text: "Hello", start: 0, end: 0.42, speaker: "0"))
        #expect(document.words.map(\.speaker) == ["0", "0", "1", "1", "1"])
        #expect(document.segments == [
            TranscriptDocument.Segment(start: 0, end: 0.95, text: "Hello there.", speaker: "0"),
            TranscriptDocument.Segment(start: 1.4, end: 2.2, text: "How are you?", speaker: "1"),
        ])
        #expect(document.warnings.isEmpty)
    }

    @Test("The language name stands in when Fish Audio sends no code")
    func languageNameFallback() throws {
        let json = Data(#"{"text":"Hola.","language":"Spanish"}"#.utf8)
        let response = try JSONDecoder().decode(FishAudioFileTranscriptionResponse.self, from: json)
        #expect(FishAudioRunner.map(response, file: file, modelID: .transcribe1Pro).language == "Spanish")
    }

    @Test("Speaker labels lose their speaker: prefix")
    func speakerLabels() {
        #expect(FishAudioRunner.speakerLabel("speaker:0") == "0")
        #expect(FishAudioRunner.speakerLabel("Speaker: 12") == "12")
        #expect(FishAudioRunner.speakerLabel("narrator") == "narrator")
        #expect(FishAudioRunner.speakerLabel("speaker:") == nil)
        #expect(FishAudioRunner.speakerLabel("") == nil)
        #expect(FishAudioRunner.speakerLabel(nil) == nil)
    }

    @Test("Turns out of order or with an impossible span are dropped or reordered")
    func turnOrdering() {
        let response = FishAudioFileTranscriptionResponse(
            text: "B. A.",
            speakerTurns: [
                FishAudioSpeakerTurn(speaker: "speaker:1", text: "B.", start: 2, end: 3),
                FishAudioSpeakerTurn(speaker: "speaker:0", text: "A.", start: 0, end: 1),
                FishAudioSpeakerTurn(speaker: "speaker:0", text: "bad", start: 5, end: 4),
                FishAudioSpeakerTurn(speaker: "speaker:0", text: "  ", start: 6, end: 7),
                FishAudioSpeakerTurn(speaker: "speaker:0", text: "untimed"),
            ]
        )
        let document = FishAudioRunner.map(response, file: file, modelID: .transcribe1Pro)
        #expect(document.segments.map(\.text) == ["A.", "B."])
        #expect(document.warnings == ["Fish Audio returned no word timings; segments are its speaker turns."])
    }

    @Test("Without turns, segments are built from the words")
    func segmentsFromWords() {
        let response = FishAudioFileTranscriptionResponse(
            text: "hello there",
            duration: 1,
            segments: [
                FishAudioTranscriptionSegment(text: "hello", start: 0, end: 0.4),
                FishAudioTranscriptionSegment(text: "there", start: 0.4, end: 0.9),
            ]
        )
        let document = FishAudioRunner.map(response, file: file, modelID: .transcribe1Pro)
        #expect(document.words.count == 2)
        #expect(document.words.allSatisfy { $0.speaker == nil })
        #expect(document.segments.count == 1)
        #expect(document.segments[0].text == "hello there")
        #expect(document.segments[0].end == 0.9)
        #expect(document.warnings.isEmpty)
    }

    @Test("Without words or turns the transcript is one untimed segment and warns")
    func untimed() throws {
        let json = Data(#"{"text":"<|speaker:0|>Hello there. [laughs]","duration":2.0}"#.utf8)
        let response = try JSONDecoder().decode(FishAudioFileTranscriptionResponse.self, from: json)
        let document = FishAudioRunner.map(response, file: file, modelID: .transcribe1Pro, warnings: ["earlier"])

        #expect(document.text == "Hello there. [laughs]")
        #expect(document.words.isEmpty)
        #expect(document.segments == [TranscriptDocument.Segment(start: 0, end: 2, text: "Hello there. [laughs]")])
        #expect(document.warnings == [
            "earlier",
            "Fish Audio returned no word timings; the transcript is one untimed segment.",
        ])
    }

    // MARK: Cues

    @Test("Sentences are the default cue mode for Fish Audio")
    func defaultCueMode() throws {
        let command = try Transcribe.parse(["a.wav"])
        #expect(command.cueMode(for: .fishAudio) == .sentences)
        #expect(command.cueMode(for: .voz) == .sentences)
        #expect(command.cueMode(for: .grok) == .segments)
        let explicit = try Transcribe.parse(["a.wav", "--cues", "segments"])
        #expect(explicit.cueMode(for: .fishAudio) == .segments)
    }

    @Test("The default sentence cues split a Fish Audio turn at its punctuation")
    func sentencesFromPunctuatedWords() throws {
        // One speaker turn holding two sentences: the turn is one segment, and
        // the punctuated words let the sentence default split it in two.
        let response = FishAudioFileTranscriptionResponse(
            text: "<|speaker:0|>How is the weather? It is sunny today.",
            duration: 8,
            segments: [
                FishAudioTranscriptionSegment(text: "how", start: 1.52, end: 1.8),
                FishAudioTranscriptionSegment(text: "is", start: 1.8, end: 2.0),
                FishAudioTranscriptionSegment(text: "the", start: 2.0, end: 2.2),
                FishAudioTranscriptionSegment(text: "weather", start: 2.2, end: 3.0),
                FishAudioTranscriptionSegment(text: "it", start: 5.0, end: 5.2),
                FishAudioTranscriptionSegment(text: "is", start: 5.2, end: 5.4),
                FishAudioTranscriptionSegment(text: "sunny", start: 5.4, end: 6.0),
                FishAudioTranscriptionSegment(text: "today", start: 6.0, end: 7.25),
            ],
            speakerTurns: [
                FishAudioSpeakerTurn(
                    speaker: "speaker:0",
                    text: "How is the weather? It is sunny today.",
                    start: 1.52,
                    end: 7.25
                )
            ]
        )
        let document = FishAudioRunner.map(response, file: file, modelID: .transcribe1Pro)
        #expect(document.segments.count == 1)

        let command = try Transcribe.parse(["a.wav", "-p", "fish-audio", "-f", "srt"])
        let adjusted = try command.cueAdjusted(document)
        #expect(adjusted.segments.map(\.text) == ["How is the weather?", "It is sunny today."])
        #expect(adjusted.segments.map(\.start) == [1.52, 5])
        #expect(adjusted.segments.allSatisfy { $0.speaker == "0" })

        let segments = try Transcribe.parse(["a.wav", "-p", "fish-audio", "--cues", "segments"])
        #expect(try segments.cueAdjusted(document) == document)
    }

    @Test("The sentence default never fails a Fish Audio run without words")
    func defaultWithoutWords() throws {
        let document = TranscriptDocument(
            provider: "fish-audio",
            sourceFile: "/tmp/a.wav",
            text: "Hello.",
            segments: [TranscriptDocument.Segment(start: 0, end: 1, text: "Hello.")]
        )
        let implicit = try Transcribe.parse(["a.wav", "-p", "fish"])
        #expect(try implicit.cueAdjusted(document) == document)
        let explicit = try Transcribe.parse(["a.wav", "-p", "fish", "--cues", "sentences"])
        #expect(throws: CLIError.self) { _ = try explicit.cueAdjusted(document) }
    }

    @Test("Pre-upload checks accept --cues sentences, --words, and --diarize, and refuse AIFF")
    func preUploadValidation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("speechkit-fish-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mp3 = directory.appendingPathComponent("talk.mp3")
        let aiff = directory.appendingPathComponent("talk.aiff")
        try Data(repeating: 0x41, count: 16).write(to: mp3)
        try Data(repeating: 0x41, count: 16).write(to: aiff)

        let capabilities = ProviderCapabilities.capabilities(for: .fishAudio)
        let command = try Transcribe.parse([
            mp3.path, "-p", "fish-audio", "--cues", "sentences", "--words", "--diarize", "-f", "srt",
        ])
        #expect(try command.validate(provider: .fishAudio, capabilities: capabilities) == [mp3])

        let rejected = try Transcribe.parse([aiff.path, "-p", "fish-audio"])
        let error = #expect(throws: CLIError.self) {
            _ = try rejected.validate(provider: .fishAudio, capabilities: capabilities)
        }
        #expect(error?.exitCode == 1)
    }

    @Test("Fish Audio always asks for timestamps itself, so it needs no word request")
    func wantsWords() {
        #expect(!Transcribe.wordSegmentProviders.contains(.fishAudio))
        #expect(!Transcribe.wantsWords(requested: false, formats: [.srt], provider: .fishAudio, cueMode: .sentences))
        #expect(Transcribe.wantsWords(requested: true, formats: [.txt], provider: .fishAudio))
    }

    // MARK: Credentials

    @Test("The key comes from SPEECHKIT_FISH_AUDIO_API_KEY, then FISH_API_KEY, then the keychain")
    func credentials() throws {
        #expect(CredentialResolver.environmentVariableName(for: .fishAudio) == "SPEECHKIT_FISH_AUDIO_API_KEY")
        #expect(CredentialResolver.environmentVariableNames(for: .fishAudio) == [
            "SPEECHKIT_FISH_AUDIO_API_KEY", "FISH_API_KEY",
        ])
        #expect(CredentialResolver.environmentVariableNames(for: .grok) == ["SPEECHKIT_GROK_API_KEY"])

        let keychain = InMemoryKeychainStore(keys: [.fishAudio: "keychain"])
        let both = CredentialResolver(
            environment: ["SPEECHKIT_FISH_AUDIO_API_KEY": "speechkit", "FISH_API_KEY": "vendor"],
            keychain: keychain
        )
        #expect(try both.resolve(provider: .fishAudio) == .apiKey("speechkit"))

        let vendor = CredentialResolver(
            environment: ["SPEECHKIT_FISH_AUDIO_API_KEY": "  ", "FISH_API_KEY": "vendor"],
            keychain: keychain
        )
        #expect(try vendor.resolve(provider: .fishAudio) == .apiKey("vendor"))

        let stored = CredentialResolver(environment: [:], keychain: keychain)
        #expect(try stored.resolve(provider: .fishAudio) == .apiKey("keychain"))

        // FISH_API_KEY belongs to Fish Audio alone.
        let other = CredentialResolver(environment: ["FISH_API_KEY": "vendor"], keychain: InMemoryKeychainStore())
        #expect(throws: CLIError.self) { _ = try other.resolve(provider: .grok) }
    }

    @Test("A missing key names both variables and exits with code three")
    func missingKey() {
        let resolver = CredentialResolver(environment: [:], keychain: InMemoryKeychainStore())
        let error = #expect(throws: CLIError.self) { _ = try resolver.resolve(provider: .fishAudio) }
        #expect(error?.exitCode == 3)
        #expect(error?.localizedDescription == "No credential for fish-audio. Pass --api-key or set SPEECHKIT_FISH_AUDIO_API_KEY or FISH_API_KEY.")
    }

    @Test("providers, keys list, and keys check see FISH_API_KEY")
    func credentialSurfaces() throws {
        let environment = ["FISH_API_KEY": "fish-secret-1234"]
        let store = InMemoryKeychainStore()

        let report = ProviderReport(provider: .fishAudio, environment: environment, store: store)
        #expect(report.credentialSource == .environment)
        #expect(report.defaultFileModel == "transcribe-1-pro")

        let rows = CredentialCheck(environment: environment, store: store).rows(for: [.fishAudio])
        #expect(rows.first?.source == .environment)
        #expect(rows.first?.environmentVariable == "SPEECHKIT_FISH_AUDIO_API_KEY")
        #expect(rows.first?.key == "fish-secret-1234".redactedAPIKey)

        let list = try KeysRunner(store: store, environment: environment).list()
        let line = try #require(list.split(separator: "\n").first { $0.hasPrefix("fish-audio") })
        #expect(line.contains("FISH_API_KEY"))
    }
}
