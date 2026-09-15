import ArgumentParser
import Foundation
import Testing
@testable import SpeechKitCLICore

/// Routing into interactive mode, the arguments it assembles, and its defaults.
@Suite("Interactive mode")
struct InteractiveTests {
    // MARK: - Routing

    @Test("No arguments on a terminal routes to interactive mode")
    func routesWithNoArguments() {
        #expect(SpeechKitCommand.wantsInteractive(arguments: [], isTTY: true))
    }

    @Test("No arguments off a terminal stays headless and prints the usage error")
    func doesNotRouteOffATerminal() {
        #expect(!SpeechKitCommand.wantsInteractive(arguments: [], isTTY: false))
        // What the headless path then does is unchanged: transcribe is still
        // the default subcommand, and it still refuses an empty file list with
        // the usage error it has always printed.
        #expect(throws: (any Error).self) { _ = try Transcribe.parse([]) }
        let message = SpeechKitCommand.message(for: ValidationError("Pass at least one audio file."))
        #expect(message == "Pass at least one audio file.")
    }

    @Test("Any argument at all stays headless, terminal or not")
    func argumentsStayHeadless() throws {
        #expect(!SpeechKitCommand.wantsInteractive(arguments: ["talk.wav", "-p", "voz"], isTTY: true))
        #expect(!SpeechKitCommand.wantsInteractive(arguments: ["--help"], isTTY: true))
        #expect(!SpeechKitCommand.wantsInteractive(arguments: ["stats"], isTTY: true))

        let command = try Transcribe.parse(["talk.wav", "-p", "voz"])
        #expect(command.files == ["talk.wav"])
        #expect(command.provider == .voz)
    }

    @Test("interactive and its ui alias both name the same command")
    func interactiveIsASubcommand() throws {
        let parsed = try SpeechKitCommand.parseAsRoot(["interactive"])
        #expect(parsed is Interactive)
        let alias = try SpeechKitCommand.parseAsRoot(["ui"])
        #expect(alias is Interactive)
    }

    // MARK: - Argument assembly

    @Test("The transcribe flow assembles the command a user would type")
    func transcribeArguments() {
        let command = InteractiveArguments.transcribe(
            InteractiveTranscribeChoices(
                files: ["a.m4a", "b.m4a"],
                provider: .voz,
                formats: [.txt, .srt],
                output: .directory("./out")
            )
        )
        #expect(command.name == "transcribe")
        #expect(command.arguments == [
            "a.m4a", "b.m4a", "-p", "voz", "-f", "txt", "-f", "srt", "-o", "./out/"
        ])
        #expect(command.displayLine == "speechkit transcribe a.m4a b.m4a -p voz -f txt -f srt -o ./out/")
    }

    @Test("Word timestamps and speaker labels become their flags")
    func transcribeFlags() {
        let command = InteractiveArguments.transcribe(
            InteractiveTranscribeChoices(
                files: ["talk.wav"],
                provider: .grok,
                formats: [.json],
                words: true,
                diarize: true,
                output: .nextToInputs
            )
        )
        #expect(command.arguments == ["talk.wav", "-p", "grok", "-f", "json", "--words", "--diarize", "-o", "./"])
    }

    @Test("Next to the inputs is spelled as the directory the first input is in")
    func transcribeBesideInputs() {
        let command = InteractiveArguments.transcribe(
            InteractiveTranscribeChoices(
                files: ["/Users/me/Recordings/talk.wav"],
                provider: .apple,
                formats: [.txt],
                output: .nextToInputs
            )
        )
        #expect(command.arguments.suffix(2) == ["-o", "/Users/me/Recordings/"])
    }

    @Test("A path with spaces is quoted in the command that is shown")
    func transcribeQuotesPaths() {
        let command = InteractiveArguments.transcribe(
            InteractiveTranscribeChoices(
                files: ["/Users/me/Voice Memos/team standup.m4a"],
                provider: .openai,
                formats: [.txt],
                output: .directory("/Users/me/My Transcripts")
            )
        )
        // The arguments themselves are never quoted: they go to the parser as
        // whole strings. Only the line shown to the user is.
        #expect(command.arguments[0] == "/Users/me/Voice Memos/team standup.m4a")
        #expect(command.displayLine == "speechkit transcribe '/Users/me/Voice Memos/team standup.m4a'"
            + " -p openai -f txt -o '/Users/me/My Transcripts/'")
    }

    @Test("A single quote in a path survives the quoting")
    func quotesASingleQuote() {
        #expect(InteractiveCommand.quote("it's here.wav") == "'it'\\''s here.wav'")
        #expect(InteractiveCommand.quote("plain.wav") == "plain.wav")
        #expect(InteractiveCommand.quote("") == "''")
    }

    @Test("stdout is assembled only for one file in one format")
    func stdoutOnlyWhenSingle() {
        let single = InteractiveTranscribeChoices(
            files: ["talk.wav"], provider: .voz, formats: [.txt], output: .standardOutput
        )
        #expect(single.allowsStandardOutput)
        #expect(InteractiveArguments.transcribe(single).arguments == ["talk.wav", "-p", "voz", "-f", "txt"])

        let twoFiles = InteractiveTranscribeChoices(
            files: ["a.wav", "b.wav"], provider: .voz, formats: [.txt], output: .standardOutput
        )
        #expect(!twoFiles.allowsStandardOutput)
        #expect(InteractiveArguments.transcribe(twoFiles).arguments.suffix(2) == ["-o", "./"])

        let twoFormats = InteractiveTranscribeChoices(
            files: ["a.wav"], provider: .voz, formats: [.txt, .json], output: .standardOutput
        )
        #expect(!twoFormats.allowsStandardOutput)
        #expect(InteractiveArguments.transcribe(twoFormats).arguments.suffix(2) == ["-o", "./"])
    }

    @Test("The assembled transcribe command parses and validates")
    func transcribeArgumentsParse() throws {
        let command = InteractiveArguments.transcribe(
            InteractiveTranscribeChoices(
                files: ["a.m4a", "b.m4a"],
                provider: .voz,
                formats: [.txt, .srt],
                words: true,
                output: .directory("./out")
            )
        )
        let parsed = try Transcribe.parse(command.arguments)
        #expect(parsed.provider == .voz)
        #expect(parsed.outputOptions.resolvedFormats == [.txt, .srt])
        #expect(parsed.transcription.words)
        #expect(parsed.outputOptions.output == "./out/")
    }

    @Test("The bench flow assembles providers, a reference directory, and a repeat count")
    func benchArguments() throws {
        let command = InteractiveArguments.bench(
            InteractiveBenchChoices(
                inputs: ["./clips"],
                providers: ["all"],
                formats: [.txt],
                referenceDirectory: "./reference",
                repeatCount: 3,
                outputDirectory: "./bench"
            )
        )
        #expect(command.arguments == [
            "./clips", "-p", "all", "-f", "txt", "--reference-dir", "./reference", "--repeat", "3", "-o", "./bench/"
        ])
        let parsed = try Bench.parse(command.arguments)
        #expect(parsed.provider == [.all])
        #expect(parsed.repeatCount == 3)
        #expect(parsed.output == "./bench/")
    }

    @Test("A repeat count of one and no reference directory leave their flags out")
    func benchOmitsDefaults() throws {
        let command = InteractiveArguments.bench(
            InteractiveBenchChoices(
                inputs: ["a.wav"],
                providers: ["voz", "apple"],
                formats: [.txt],
                outputDirectory: "./bench/"
            )
        )
        #expect(command.arguments == ["a.wav", "-p", "voz", "-p", "apple", "-f", "txt", "-o", "./bench/"])
        let parsed = try Bench.parse(command.arguments)
        #expect(parsed.provider == [.one(.voz), .one(.apple)])
        #expect(parsed.repeatCount == 1)
    }

    // MARK: - Provider status

    @Test("Each credential source has its own status line")
    func statusFromCredentials() {
        #expect(ProviderStatusText.text(
            for: .grok, source: .keychain, vozCached: false, appleAvailable: true
        ) == "key: keychain")
        #expect(ProviderStatusText.text(
            for: .openai, source: .environment, vozCached: false, appleAvailable: true
        ) == "key: env")
        #expect(ProviderStatusText.text(
            for: .gemini, source: .notFound, vozCached: false, appleAvailable: true
        ) == "no key")
    }

    @Test("The on-device providers report their model instead of a key")
    func statusOnDevice() {
        #expect(ProviderStatusText.text(
            for: .voz, source: .notNeeded, vozCached: true, appleAvailable: true
        ) == "on device, ready")
        #expect(ProviderStatusText.text(
            for: .voz, source: .notNeeded, vozCached: false, appleAvailable: true
        ) == "on device, model not downloaded")
        #expect(ProviderStatusText.text(
            for: .apple, source: .notNeeded, vozCached: true, appleAvailable: true
        ) == "on device, ready")
        #expect(ProviderStatusText.text(
            for: .apple, source: .notNeeded, vozCached: true, appleAvailable: false
        ) == "on device, needs macOS 26")
    }

    @Test("Only a missing key makes a provider unrunnable")
    func statusRunnable() {
        #expect(ProviderStatusText.isRunnable(source: .keychain))
        #expect(ProviderStatusText.isRunnable(source: .notNeeded))
        #expect(!ProviderStatusText.isRunnable(source: .notFound))
    }

    // MARK: - Defaults

    private func record(
        provider: String,
        formats: [String],
        outputDirectory: String? = nil,
        status: String = HistoryStatus.ok,
        command: String = "transcribe",
        secondsAgo: Double
    ) -> HistoryRecord {
        HistoryRecord(
            timestamp: Date(timeIntervalSince1970: 1_789_000_000 - secondsAgo),
            command: command,
            provider: provider,
            fileName: "talk.wav",
            wallSeconds: 2,
            formats: formats,
            outputDirectory: outputDirectory,
            status: status
        )
    }

    @Test("The defaults come from the most recent successful transcribe run")
    func defaultsFromHistory() {
        let defaults = InteractiveDefaults.fromHistory([
            record(provider: "apple", formats: ["json"], outputDirectory: "/tmp/old", secondsAgo: 600),
            record(provider: "voz", formats: ["txt", "srt"], outputDirectory: "/tmp/out", secondsAgo: 60)
        ])
        #expect(defaults.provider == .voz)
        #expect(defaults.formats == [.txt, .srt])
        #expect(defaults.outputDirectory == "/tmp/out")
    }

    @Test("A failed run and a bench row are not preferences")
    func defaultsIgnoreFailuresAndBench() {
        let defaults = InteractiveDefaults.fromHistory([
            record(provider: "voz", formats: ["txt"], outputDirectory: "/tmp/out", secondsAgo: 300),
            record(provider: "grok", formats: ["vtt"], status: HistoryStatus.provider, secondsAgo: 120),
            record(provider: "meta", formats: ["json"], command: "bench", secondsAgo: 60)
        ])
        #expect(defaults.provider == .voz)
        #expect(defaults.formats == [.txt])
    }

    @Test("The last run to name a directory supplies it, even if a later one went to stdout")
    func defaultsKeepLastDirectory() {
        let defaults = InteractiveDefaults.fromHistory([
            record(provider: "voz", formats: ["txt"], outputDirectory: "/tmp/out", secondsAgo: 300),
            record(provider: "apple", formats: ["txt"], secondsAgo: 60)
        ])
        #expect(defaults.provider == .apple)
        #expect(defaults.outputDirectory == "/tmp/out")
    }

    @Test("An empty history has no defaults at all")
    func defaultsEmpty() {
        #expect(InteractiveDefaults.fromHistory([]) == .empty)
        #expect(InteractiveDefaults.empty.provider == nil)
        #expect(InteractiveDefaults.empty.formats.isEmpty)
    }

    @Test("The first run falls back to VOZ, then Apple, then the first provider with a key")
    func firstRunFallback() {
        #expect(InteractiveDefaults.firstRunProvider(
            vozCached: true, appleAvailable: true, hasKey: { _ in false }
        ) == .voz)
        #expect(InteractiveDefaults.firstRunProvider(
            vozCached: false, appleAvailable: true, hasKey: { _ in false }
        ) == .apple)
        #expect(InteractiveDefaults.firstRunProvider(
            vozCached: false, appleAvailable: false, hasKey: { $0 == .grok }
        ) == .grok)
        // Nothing is usable yet: VOZ is still the offer, and choosing it asks
        // to download the model.
        #expect(InteractiveDefaults.firstRunProvider(
            vozCached: false, appleAvailable: false, hasKey: { _ in false }
        ) == .voz)
    }

    @Test("The recorded output directory survives a history round trip")
    func outputDirectoryRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("speechkit-interactive-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = HistoryStore(root: root)
        try await store.append(record(provider: "voz", formats: ["txt"], outputDirectory: "/tmp/out", secondsAgo: 0))
        let read = try await store.read()
        #expect(read.records.first?.outputDirectory == "/tmp/out")
        #expect(InteractiveDefaults.fromHistory(read.records).outputDirectory == "/tmp/out")
    }

    @Test("A transcript written to stdout records no output directory")
    func outputDirectoryOnlyForDirectories() {
        #expect(Transcribe.outputDirectory(of: .standardOutput) == nil)
        #expect(Transcribe.outputDirectory(of: .file(URL(fileURLWithPath: "/tmp/a.txt"))) == nil)
        #expect(Transcribe.outputDirectory(
            of: .directory(URL(fileURLWithPath: "/tmp/out", isDirectory: true))
        ) == "/tmp/out")
    }

    // MARK: - Files

    @Test("A glob typed into a prompt is expanded, since there is no shell to do it")
    func expandsGlobs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("speechkit-glob-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["one.wav", "two.wav", "notes.txt"] {
            try Data().write(to: root.appendingPathComponent(name))
        }

        let matched = InteractiveFiles.expand(root.path + "/*.wav")
        #expect(matched == [root.path + "/one.wav", root.path + "/two.wav"])
        // A plain path is passed through, and so is a pattern that matches
        // nothing, so the run fails naming what was typed.
        #expect(InteractiveFiles.expand(" talk.wav ") == ["talk.wav"])
        #expect(InteractiveFiles.expand(root.path + "/*.flac") == [root.path + "/*.flac"])
    }

    @Test("Interactive mode refuses to start without a terminal")
    func refusesWithoutATerminal() {
        #expect(Interactive.notATerminalMessage.contains("needs a terminal"))
        // The test process has no terminal on standard input, so the guard in
        // `run()` is the path taken here.
        #expect(!Terminal.isInteractive())
    }
}
