import ArgumentParser
import Foundation
import Testing
@testable import SpeechKitCLICore

/// A real `transcribe` run, recorded in a history of its own.
///
/// Apple transcribes on device in about a second and costs nothing, so this
/// runs whenever the operating system supports it. `SPEECHKIT_HISTORY_DIR`
/// points the store at a temporary directory, so the machine's own history is
/// never touched. The suite is serialized because that variable is process
/// wide.
@Suite("History recording", .serialized)
struct HistoryRecordingTests {
    @Test("a transcribe run records one ok row with words and a wall time")
    func transcribeRecordsARun() async throws {
        guard #available(macOS 26.0, *) else { return }

        let sample = try IntegrationTests.makeSample()
        defer { sample.remove() }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("speechkit-history-e2e-\(UUID().uuidString)", isDirectory: true)
        let output = sample.directory.appendingPathComponent("out", isDirectory: true)
        setenv(HistoryStore.directoryVariable, root.path, 1)
        defer {
            unsetenv(HistoryStore.directoryVariable)
            try? FileManager.default.removeItem(at: root)
        }

        let command = try Transcribe.parse([sample.url.path, "-p", "apple", "-o", output.path + "/"])
        try await command.run()

        let read = try await HistoryStore(root: root).read()
        #expect(read.skippedLines == 0)
        #expect(read.records.count == 1)

        let record = try #require(read.records.first)
        #expect(record.status == "ok")
        #expect(record.command == "transcribe")
        #expect(record.provider == "apple")
        #expect(record.fileName == sample.url.lastPathComponent)
        #expect(record.filePath == sample.url.standardizedFileURL.path)
        #expect(record.words > 0)
        #expect(record.chars > 0)
        #expect(record.wallSeconds > 0)
        #expect(record.formats == ["txt"])
        #expect(record.cliVersion == SpeechKitCommand.configuration.version)
        #expect((record.inputBytes ?? 0) > 0)
    }

    @Test("--no-history records nothing for the same run")
    func noHistoryRecordsNothing() async throws {
        guard #available(macOS 26.0, *) else { return }

        let sample = try IntegrationTests.makeSample()
        defer { sample.remove() }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("speechkit-history-e2e-\(UUID().uuidString)", isDirectory: true)
        let output = sample.directory.appendingPathComponent("out", isDirectory: true)
        setenv(HistoryStore.directoryVariable, root.path, 1)
        defer {
            unsetenv(HistoryStore.directoryVariable)
            try? FileManager.default.removeItem(at: root)
        }

        let command = try Transcribe.parse(
            [sample.url.path, "-p", "apple", "-o", output.path + "/", "--no-history"]
        )
        try await command.run()

        #expect(FileManager.default.fileExists(atPath: root.path) == false)
    }
}
