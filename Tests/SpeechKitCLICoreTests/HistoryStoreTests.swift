import Foundation
import Testing
@testable import SpeechKitCLICore

/// Appending, reading, and opting out of the usage history.
@Suite("History store")
struct HistoryStoreTests {
    /// A store rooted in a fresh temporary directory.
    private func makeStore() -> (store: HistoryStore, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("speechkit-history-\(UUID().uuidString)", isDirectory: true)
        return (HistoryStore(root: root), root)
    }

    private func record(
        provider: String = "voz",
        file: String = "talk.wav",
        status: String = HistoryStatus.ok
    ) -> HistoryRecord {
        HistoryRecord(
            timestamp: Date(timeIntervalSince1970: 1_789_000_000.125),
            cliVersion: "0.7.0",
            command: "transcribe",
            provider: provider,
            model: "voz-1",
            fileName: file,
            filePath: "/tmp/\(file)",
            inputBytes: 4096,
            audioSeconds: 120,
            wallSeconds: 3,
            words: 210,
            chars: 1_150,
            formats: ["txt", "srt"],
            wantsWords: true,
            wantsDiarization: false,
            status: status
        )
    }

    @Test("a record survives a round trip through the file")
    func roundTrip() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let written = record()
        try await store.append(written)
        let read = try await store.read()

        #expect(read.skippedLines == 0)
        #expect(read.records == [written])
        // The derived factor is stored, not recomputed on read.
        #expect(read.records[0].realtimeFactor == 40)
    }

    @Test("the record is one line of sorted-key JSON with an ISO 8601 timestamp")
    func lineShape() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try await store.append(record())
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)

        #expect(lines.count == 2)
        #expect(lines[1].isEmpty)
        #expect(lines[0].hasPrefix("{\"audioSeconds\":120,\"chars\":1150,\"cliVersion\":\"0.7.0\""))
        #expect(text.contains("\"timestamp\":\"2026-09-10T00:26:40.125Z\""))
        #expect(!text.contains("\"repeat\""))
    }

    @Test("the directory is 0700 and the file is 0600")
    func permissions() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try await store.append(record())
        let manager = FileManager.default
        let directory = try manager.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber
        let file = try manager.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? NSNumber

        #expect(directory?.int16Value == 0o700)
        #expect(file?.int16Value == 0o600)
    }

    @Test("fifty concurrent appends produce fifty intact lines")
    func concurrentAppends() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<50 {
                group.addTask {
                    try? await store.append(self.record(file: "file-\(index).wav"))
                }
            }
        }

        let read = try await store.read()
        #expect(read.skippedLines == 0)
        #expect(read.records.count == 50)
        #expect(Set(read.records.map(\.fileName)).count == 50)

        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(text.hasSuffix("\n"))
        #expect(text.split(separator: "\n").count == 50)
    }

    @Test("a corrupt line is skipped and counted, and the rest still read")
    func corruptLineSkipped() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try await store.append(record(provider: "apple"))
        let handle = try FileHandle(forWritingTo: store.fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"command\":\"transcribe\",\n".utf8))
        try handle.close()
        try await store.append(record(provider: "grok"))

        let read = try await store.read()
        #expect(read.skippedLines == 1)
        #expect(read.records.map(\.provider) == ["apple", "grok"])
    }

    @Test("unknown keys on a line are ignored")
    func unknownKeysIgnored() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try await store.append(record())
        var line = try String(contentsOf: store.fileURL, encoding: .utf8)
        line = line.replacingOccurrences(of: "{\"", with: "{\"futureField\":[1,2,3],\"")
        try line.write(to: store.fileURL, atomically: true, encoding: .utf8)

        let read = try await store.read()
        #expect(read.skippedLines == 0)
        #expect(read.records.count == 1)
    }

    @Test("reading a store that was never written finds nothing")
    func missingFileReadsEmpty() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(try await store.read() == .empty)
        #expect(await store.exists == false)
    }

    @Test("clear deletes the file, and says so only when there was one")
    func clear() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(try await store.clear() == false)
        try await store.append(record())
        #expect(try await store.clear() == true)
        #expect(await store.exists == false)
    }

    // MARK: - Opt-out

    @Test("--no-history and SPEECHKIT_NO_HISTORY both turn recording off")
    func optOut() {
        #expect(HistoryRecorder.isEnabled(noHistory: false, environment: [:]))
        #expect(!HistoryRecorder.isEnabled(noHistory: true, environment: [:]))
        #expect(!HistoryRecorder.isEnabled(noHistory: false, environment: ["SPEECHKIT_NO_HISTORY": "1"]))
        // Anything non-empty means off: a variable set to 0 in a profile is far
        // more likely to mean "off" than "on".
        #expect(!HistoryRecorder.isEnabled(noHistory: false, environment: ["SPEECHKIT_NO_HISTORY": "0"]))
        #expect(HistoryRecorder.isEnabled(noHistory: false, environment: ["SPEECHKIT_NO_HISTORY": ""]))
    }

    @Test("an opted-out recorder creates nothing at all")
    func optOutCreatesNothing() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("speechkit-history-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let byFlag = HistoryRecorder(noHistory: true, environment: [:], root: root)
        await byFlag.record(record())

        let byEnvironment = HistoryRecorder(
            noHistory: false,
            environment: ["SPEECHKIT_NO_HISTORY": "1"],
            root: root
        )
        await byEnvironment.record(record())

        #expect(byFlag.isEnabled == false)
        #expect(byEnvironment.isEnabled == false)
        #expect(FileManager.default.fileExists(atPath: root.path) == false)
    }

    @Test("a recorder that is on writes through to the store")
    func recorderWrites() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("speechkit-history-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let recorder = HistoryRecorder(noHistory: false, environment: [:], root: root)
        await recorder.record(record())

        #expect(recorder.isEnabled)
        #expect(try await HistoryStore(root: root).read().records.count == 1)
    }

    @Test("a store that cannot be written never fails the run")
    func recordingNeverThrows() async {
        // A root under /dev/null can never be created, so the append fails and
        // the recorder swallows it.
        let recorder = HistoryRecorder(
            noHistory: false,
            environment: [:],
            root: URL(fileURLWithPath: "/dev/null/speechkit", isDirectory: true)
        )
        await recorder.record(record())
    }

    // MARK: - Error classes

    @Test("failures are recorded as a short error class")
    func errorClasses() {
        #expect(HistoryRecord.status(for: CLIError.missingCredential(.grok)) == "credential")
        #expect(HistoryRecord.status(for: CLIError.fileTooLarge(URL(fileURLWithPath: "/tmp/a.wav"), limit: 10)) == "validation")
        #expect(HistoryRecord.status(for: CLIError.writeFailed(URL(fileURLWithPath: "/tmp/a.txt"), reason: "full")) == "write")
        #expect(HistoryRecord.status(for: CLIError.transcriptionFailed(file: URL(fileURLWithPath: "/tmp/a.wav"), reason: "500")) == "provider")
        #expect(HistoryRecord.status(for: CocoaError(.fileNoSuchFile)) == "provider")
    }

    @Test("an error message keeps its first line and no more than 200 characters")
    func errorMessages() {
        #expect(HistoryRecord.errorMessage("failed\n{\n  \"error\": true\n}") == "failed")
        #expect(HistoryRecord.errorMessage("   ") == nil)
        #expect(HistoryRecord.errorMessage(String(repeating: "x", count: 500))?.count == 200)
    }
}
