import Foundation
import Testing
@testable import SpeechKitCLICore

@Suite("Output writing")
struct OutputWriterTests {
    @Test("Output lands next to the input by default")
    func defaultDestination() {
        let writer = OutputWriter(
            outputDirectory: nil,
            explicitOutput: nil,
            writesToStandardOutput: false,
            overwrite: false,
            console: Console(verbosity: .quiet)
        )
        let url = writer.destinationURL(for: URL(fileURLWithPath: "/tmp/talk.m4a"), fileExtension: "json")
        #expect(url.path == "/tmp/talk.json")
    }

    @Test("--output-dir redirects the output")
    func outputDirectory() {
        let writer = OutputWriter(
            outputDirectory: URL(fileURLWithPath: "/tmp/subs", isDirectory: true),
            explicitOutput: nil,
            writesToStandardOutput: false,
            overwrite: false,
            console: Console(verbosity: .quiet)
        )
        let url = writer.destinationURL(for: URL(fileURLWithPath: "/tmp/talk.m4a"), fileExtension: "txt")
        #expect(url.path == "/tmp/subs/talk.txt")
    }

    @Test("Existing files are skipped without --overwrite and replaced with it")
    func overwrite() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("speechkit-cli-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("talk.wav")
        try Data("audio".utf8).write(to: input)

        let skipping = OutputWriter(
            outputDirectory: nil,
            explicitOutput: nil,
            writesToStandardOutput: false,
            overwrite: false,
            console: Console(verbosity: .quiet)
        )
        let first = try skipping.write("one\n", for: input, fileExtension: "txt")
        #expect(first == .file(directory.appendingPathComponent("talk.txt")))

        let second = try skipping.write("two\n", for: input, fileExtension: "txt")
        #expect(second == .skipped(directory.appendingPathComponent("talk.txt")))
        #expect(try String(contentsOf: directory.appendingPathComponent("talk.txt"), encoding: .utf8) == "one\n")

        let replacing = OutputWriter(
            outputDirectory: nil,
            explicitOutput: nil,
            writesToStandardOutput: false,
            overwrite: true,
            console: Console(verbosity: .quiet)
        )
        _ = try replacing.write("three\n", for: input, fileExtension: "txt")
        #expect(try String(contentsOf: directory.appendingPathComponent("talk.txt"), encoding: .utf8) == "three\n")
    }

    @Test("Exit codes follow the plan")
    func exitCodes() {
        #expect(CLIError.missingProvider.exitCode == 1)
        #expect(CLIError.transcriptionFailed(file: URL(fileURLWithPath: "/tmp/a.wav"), reason: "boom").exitCode == 2)
        #expect(CLIError.appleUnavailable.exitCode == 3)
    }
}
