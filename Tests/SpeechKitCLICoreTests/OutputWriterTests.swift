import Foundation
import Testing
@testable import SpeechKitCLICore

@Suite("Output writing")
struct OutputWriterTests {
    @Test("Output goes to stdout by default")
    func defaultDestination() {
        let writer = OutputWriter(target: .standardOutput, overwrite: false, console: Console(verbosity: .quiet))
        #expect(writer.destinationURL(for: URL(fileURLWithPath: "/tmp/talk.m4a"), fileExtension: "json") == nil)
    }

    @Test("A directory --output names files after the input stem")
    func outputDirectory() {
        let writer = OutputWriter(
            target: .directory(URL(fileURLWithPath: "/tmp/subs", isDirectory: true)),
            overwrite: false,
            console: Console(verbosity: .quiet)
        )
        let url = writer.destinationURL(for: URL(fileURLWithPath: "/tmp/talk.m4a"), fileExtension: "txt")
        #expect(url?.path == "/tmp/subs/talk.txt")
    }

    @Test("A file --output is used verbatim")
    func outputFile() {
        let writer = OutputWriter(
            target: .file(URL(fileURLWithPath: "/tmp/named.srt")),
            overwrite: false,
            console: Console(verbosity: .quiet)
        )
        let url = writer.destinationURL(for: URL(fileURLWithPath: "/tmp/talk.m4a"), fileExtension: "txt")
        #expect(url?.path == "/tmp/named.srt")
    }

    @Test("--output resolves to a directory when it exists or ends with a slash")
    func targetResolution() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("speechkit-cli-target-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        func target(_ output: String?) throws -> OutputTarget {
            var arguments = ["a.wav", "-p", "grok"]
            if let output { arguments += ["-o", output] }
            return try Transcribe.parse(arguments).outputOptions.target
        }

        #expect(try target(nil) == .standardOutput)
        #expect(try target(directory.path) == .directory(URL(fileURLWithPath: directory.path, isDirectory: true)))
        guard case .directory = try target("/tmp/does-not-exist-\(UUID().uuidString)/") else {
            Issue.record("A trailing slash should mean a directory")
            return
        }
        let file = directory.appendingPathComponent("talk.txt")
        #expect(try target(file.path) == .file(URL(fileURLWithPath: file.path)))
    }

    @Test("Existing files are skipped without --overwrite and replaced with it")
    func overwrite() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("speechkit-cli-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("talk.wav")
        try Data("audio".utf8).write(to: input)

        let skipping = OutputWriter(target: .directory(directory), overwrite: false, console: Console(verbosity: .quiet))
        let first = try skipping.write("one\n", for: input, fileExtension: "txt")
        #expect(first == .file(directory.appendingPathComponent("talk.txt")))

        let second = try skipping.write("two\n", for: input, fileExtension: "txt")
        #expect(second == .skipped(directory.appendingPathComponent("talk.txt")))
        #expect(try String(contentsOf: directory.appendingPathComponent("talk.txt"), encoding: .utf8) == "one\n")

        let replacing = OutputWriter(target: .directory(directory), overwrite: true, console: Console(verbosity: .quiet))
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
