import Foundation
import SpeechKitVoz
import Testing
@testable import SpeechKitCLICore

@Suite("VOZ")
struct VozRunnerTests {
    private let file = URL(fileURLWithPath: "/tmp/talk.wav")

    /// A response shaped like one VOZ returns for a short spoken sentence.
    private func response() -> VozFileTranscriptionResponse {
        VozFileTranscriptionResponse(
            text: "The quick brown fox jumps over the lazy dog.",
            words: [
                VozFileTranscriptionWord(text: "The", startTime: 0.0, endTime: 0.16),
                VozFileTranscriptionWord(text: "quick", startTime: 0.16, endTime: 0.48),
                VozFileTranscriptionWord(text: "brown", startTime: 0.48, endTime: 0.80),
                VozFileTranscriptionWord(text: "fox", startTime: 0.80, endTime: 1.04),
                VozFileTranscriptionWord(text: "jumps", startTime: 1.04, endTime: 1.36),
                VozFileTranscriptionWord(text: "over", startTime: 1.36, endTime: 1.60),
                VozFileTranscriptionWord(text: "the", startTime: 1.60, endTime: 1.76),
                VozFileTranscriptionWord(text: "lazy", startTime: 1.76, endTime: 2.08),
                VozFileTranscriptionWord(text: "dog.", startTime: 2.08, endTime: 2.40),
            ],
            duration: 2.6,
            processingTime: 0.4
        )
    }

    @Test("A VOZ response maps to words, cue segments, and a duration")
    func mapping() {
        let document = VozRunner.map(response(), file: file)

        #expect(document.provider == "voz")
        #expect(document.model == VozRunner.defaultModel)
        #expect(document.sourceFile == file.path)
        #expect(document.text == "The quick brown fox jumps over the lazy dog.")
        #expect(document.duration == 2.6)
        // VOZ reports no language, no speaker, and no confidence.
        #expect(document.language == nil)
        #expect(document.words.count == 9)
        #expect(document.words.allSatisfy { $0.speaker == nil && $0.confidence == nil })
        #expect(document.words.first?.start == 0.0)
        #expect(document.words.first?.end == 0.16)
        #expect(document.words.last?.text == "dog.")

        #expect(document.segments.count == 1)
        #expect(document.segments[0].start == 0.0)
        #expect(document.segments[0].end == 2.40)
        #expect(document.segments[0].speaker == nil)
        #expect(document.hasTimings)
    }

    @Test("--max-cue-chars reaches VOZ segment building")
    func cueLimitApplies() {
        // Four characters is narrower than any two of the words together, so
        // every cue holds one word.
        let tight = CueBuilder(maxCueDuration: 7, maxCueChars: 4)
        let narrow = VozRunner.map(response(), file: file, cueBuilder: tight)

        #expect(narrow.segments.count == narrow.words.count)
        #expect(narrow.segments.map(\.text) == narrow.words.map(\.text))
        #expect(narrow.segments == RunnerSupport.orderedSegments(narrow.segments))
    }

    @Test("The capability row describes an on-device model with no credential")
    func capabilities() {
        let capabilities = ProviderCapabilities.capabilities(for: .voz)
        #expect(capabilities.defaultFileModel == "voz v0.5.0")
        #expect(capabilities.supportsWordTimestamps)
        #expect(capabilities.supportsSegments)
        #expect(capabilities.supportsDiarization == false)
        #expect(capabilities.languageStyle == .none)
        #expect(capabilities.maxFileBytes == nil)
        #expect(capabilities.acceptedExtensions == nil)
        #expect(capabilities.requiresMacOS26 == false)
        #expect(CLIProvider.voz.requiresCredential == false)
        #expect(CLIProvider.voz.speechKitProvider == nil)

        let report = ProviderReport(provider: .voz, environment: [:], store: nil)
        #expect(report.minimumMacOS == "15")
        #expect(report.credentialSource == .notNeeded)
    }

    @Test("The providers table includes a voz row")
    func providersTable() {
        let reports = ProviderReport.all(environment: [:], store: nil)
        #expect(reports.map(\.provider).contains("voz"))
        let table = ProviderReport.table(reports)
        let row = table.split(separator: "\n").first { $0.hasPrefix("voz") }
        #expect(row?.contains("voz v0.5.0") == true)
        #expect(row?.contains("not needed") == true)
    }

    @Test("languages voz says the model takes no hint")
    func languages() {
        #expect(LanguageMapping.validValues(for: .voz) == [])
        let report = LanguageReport.make(for: .voz)
        #expect(report.provider == "voz")
        #expect(report.style == "none")
        #expect(report.values.isEmpty)
        #expect(report.note.contains("does not take a language hint"))
        #expect(report.render() == report.note + "\n")
    }

    @Test("voz status reports the cache without an in-memory state")
    func statusReport() throws {
        let missing = VozStatusReport.make(cached: false)
        #expect(missing.model == "voz v0.5.0")
        #expect(missing.cached == false)
        #expect(missing.cacheLocation == "VOZ managed cache")
        #expect(missing.render().contains("cached: no"))
        #expect(missing.render().contains("speechkit voz prepare"))

        let present = VozStatusReport.make(cached: true)
        #expect(present.render().contains("cached: yes"))
        #expect(present.render().contains("speechkit voz prepare") == false)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let object = try JSONSerialization.jsonObject(
            with: try encoder.encode(present)
        ) as? [String: Any]
        #expect(object?["cached"] as? Bool == true)
        #expect(object?["model"] as? String == "voz v0.5.0")
        #expect(object?["state"] == nil)
    }

    @Test("voz subcommands parse")
    func parsing() throws {
        #expect(try Voz.Status.parse([]).json == false)
        #expect(try Voz.Status.parse(["--json"]).json)
        #expect(try Voz.Prepare.parse([]).downloadOnly == false)
        #expect(try Voz.Prepare.parse(["--download-only"]).downloadOnly)

        let status = try Voz.parseAsRoot(["status", "--json"]) as? Voz.Status
        #expect(status?.json == true)
        let prepare = try Voz.parseAsRoot(["prepare", "--download-only"]) as? Voz.Prepare
        #expect(prepare?.downloadOnly == true)
        // `status` is the default subcommand, so a bare `speechkit voz` reports.
        #expect(try Voz.parseAsRoot([]) is Voz.Status)
    }

    @Test("transcribe parses --no-download and turns it into a run context")
    func noDownloadFlag() throws {
        let plain = try Transcribe.parse(["a.wav", "-p", "voz"])
        #expect(plain.transcription.noDownload == false)

        let refused = try Transcribe.parse(["a.wav", "-p", "voz", "--no-download"])
        #expect(refused.transcription.noDownload)

        let context = RunContext(allowsModelDownload: false)
        #expect(context.allowsModelDownload == false)
        #expect(RunContext().allowsModelDownload)
    }

    @Test("A refused download and a failed preparation both exit with code 3")
    func errorCodes() {
        let refused = CLIError.modelDownloadRefused(provider: .voz, size: "about 337 MB")
        #expect(refused.exitCode == 3)
        #expect(refused.localizedDescription.contains("speechkit voz prepare"))
        #expect(refused.localizedDescription.contains("about 337 MB"))

        let notReady = CLIError.modelNotReady(provider: .voz, reason: "the network went away")
        #expect(notReady.exitCode == 3)
        #expect(notReady.localizedDescription.contains("the network went away"))

        // A file that fails once the model is ready is a per-file failure.
        #expect(
            CLIError.transcriptionFailed(file: URL(fileURLWithPath: "/tmp/a.wav"), reason: "x").exitCode == 2
        )
        #expect(VozModelSession.message(for: VozError.notPrepared).contains("Prepare the VOZ model"))
    }
}
