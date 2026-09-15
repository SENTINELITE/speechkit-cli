import ArgumentParser
import Foundation

/// One recorded run: one input file through one provider.
///
/// The record is everything `stats` needs and nothing else. Transcript text,
/// API keys, reference transcripts, and word error rates are never written
/// here: the history file is not a second copy of anyone's audio content.
public struct HistoryRecord: Codable, Sendable, Equatable {
    /// When the run finished.
    public var timestamp: Date
    /// The `speechkit --version` of the run.
    public var cliVersion: String
    /// The command that produced the row: `transcribe`, `bench`, or `keys check`.
    public var command: String
    /// The `--provider` value.
    public var provider: String
    /// The model the provider reported, when it names one.
    public var model: String?
    /// The input file name, without its directory.
    public var fileName: String
    /// The full input path, absent for the generated `keys check` probe clip.
    public var filePath: String?
    /// The size of the input file, in bytes.
    public var inputBytes: Int?
    /// The audio duration, in seconds.
    public var audioSeconds: Double?
    /// The wall time of the run, in seconds.
    public var wallSeconds: Double
    /// Audio seconds divided by wall seconds, for sorting single rows.
    public var realtimeFactor: Double?
    /// The words of transcript text.
    public var words: Int
    /// The characters of transcript text.
    public var chars: Int
    /// The formats written, as `--format` values.
    public var formats: [String]
    /// Whether word timings were asked for.
    public var wantsWords: Bool
    /// Whether speaker labels were asked for.
    public var wantsDiarization: Bool
    /// The `--repeat` count, for `bench`.
    public var repeatCount: Int?
    /// ``HistoryStatus/ok``, or the class of error that failed the run.
    public var status: String
    /// The first line of the failure, capped at ``errorMessageLimit`` characters.
    public var errorMessage: String?

    private enum CodingKeys: String, CodingKey {
        case timestamp
        case cliVersion
        case command
        case provider
        case model
        case fileName
        case filePath
        case inputBytes
        case audioSeconds
        case wallSeconds
        case realtimeFactor
        case words
        case chars
        case formats
        case wantsWords
        case wantsDiarization
        case repeatCount = "repeat"
        case status
        case errorMessage
    }

    /// Creates a record.
    ///
    /// ``realtimeFactor`` is derived from the audio and wall seconds unless it
    /// is passed, because a stored factor that disagrees with its own row would
    /// be worse than no factor at all.
    public init(
        timestamp: Date = Date(),
        cliVersion: String = SpeechKitCommand.configuration.version,
        command: String,
        provider: String,
        model: String? = nil,
        fileName: String,
        filePath: String? = nil,
        inputBytes: Int? = nil,
        audioSeconds: Double? = nil,
        wallSeconds: Double,
        realtimeFactor: Double? = nil,
        words: Int = 0,
        chars: Int = 0,
        formats: [String] = [],
        wantsWords: Bool = false,
        wantsDiarization: Bool = false,
        repeatCount: Int? = nil,
        status: String = HistoryStatus.ok,
        errorMessage: String? = nil
    ) {
        self.timestamp = timestamp
        self.cliVersion = cliVersion
        self.command = command
        self.provider = provider
        self.model = model
        self.fileName = fileName
        self.filePath = filePath
        self.inputBytes = inputBytes
        self.audioSeconds = audioSeconds
        self.wallSeconds = wallSeconds
        if let realtimeFactor {
            self.realtimeFactor = realtimeFactor
        } else if let audioSeconds, audioSeconds > 0, wallSeconds > 0 {
            self.realtimeFactor = audioSeconds / wallSeconds
        } else {
            self.realtimeFactor = nil
        }
        self.words = words
        self.chars = chars
        self.formats = formats
        self.wantsWords = wantsWords
        self.wantsDiarization = wantsDiarization
        self.repeatCount = repeatCount
        self.status = status
        self.errorMessage = errorMessage
    }

    /// A Boolean value indicating whether the run succeeded.
    public var succeeded: Bool { status == HistoryStatus.ok }

    /// What counts as one file: the full path when there is one, the name otherwise.
    public var fileIdentity: String { filePath ?? fileName }

    /// The longest ``errorMessage`` that is stored.
    public static let errorMessageLimit = 200

    /// An encoder that writes one stable line per record.
    ///
    /// Keys are sorted so two runs of the same shape produce byte-identical
    /// lines, which makes the file diffable and the tests golden.
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(timestampFormatter.string(from: date))
        }
        return encoder
    }

    /// A decoder that accepts the timestamps ``encoder`` writes.
    ///
    /// A timestamp without fractional seconds is accepted too, so a file
    /// written by hand or by another tool still reads.
    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = timestampFormatter.date(from: text) { return date }
            if let date = plainTimestampFormatter.date(from: text) { return date }
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Not an ISO 8601 timestamp: \(text)")
            )
        }
        return decoder
    }

    /// ISO 8601 with fractional seconds.
    ///
    /// `ISO8601DateFormatter` is thread safe for formatting and parsing once
    /// configured, and nothing here mutates it after this closure returns.
    nonisolated(unsafe) static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// ISO 8601 without fractional seconds, for reading.
    nonisolated(unsafe) static let plainTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Returns the error class stored in ``status`` for a failure.
    ///
    /// The classes are coarse on purpose: `stats` answers "how often does this
    /// provider fail", not "which HTTP code did it return".
    public static func status(for error: Error) -> String {
        guard let error = error as? CLIError else { return HistoryStatus.provider }
        switch error {
        case .missingCredential, .missingProvider, .keychainFailure:
            return HistoryStatus.credential
        case .writeFailed:
            return HistoryStatus.write
        case .transcriptionFailed:
            return HistoryStatus.provider
        case .usage, .unsupportedCapability, .invalidModel, .invalidLanguage, .fileNotFound,
             .inputIsDirectory, .fileUnreadable, .unsupportedFileExtension, .fileTooLarge,
             .noRunnableProviders, .appleUnavailable, .modelNotReady, .modelDownloadRefused,
             .noTimingData, .subtitlesUnsupported:
            return HistoryStatus.validation
        }
    }

    /// Returns the first line of a failure, capped for storage.
    public static func errorMessage(_ text: String) -> String? {
        let first = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !first.isEmpty else { return nil }
        return first.count > errorMessageLimit ? String(first.prefix(errorMessageLimit)) : first
    }
}

/// The values ``HistoryRecord/status`` takes.
public enum HistoryStatus {
    /// The run succeeded.
    public static let ok = "ok"
    /// No usable credential.
    public static let credential = "credential"
    /// The provider rejected the request or returned nothing usable.
    public static let provider = "provider"
    /// The run was refused before anything left the machine.
    public static let validation = "validation"
    /// The transcript could not be written.
    public static let write = "write"
}

/// What a read of the history file found.
public struct HistoryReadResult: Sendable, Equatable {
    /// The records, oldest first, in the order they were appended.
    public let records: [HistoryRecord]
    /// How many lines could not be decoded.
    public let skippedLines: Int

    /// Creates a result.
    public init(records: [HistoryRecord], skippedLines: Int = 0) {
        self.records = records
        self.skippedLines = skippedLines
    }

    /// A result with nothing in it.
    public static let empty = HistoryReadResult(records: [], skippedLines: 0)
}

/// Appends and reads the local run history.
///
/// Storage is append-only JSON Lines, one object per file per run. The actor is
/// the lock: a batch of eight concurrent uploads posts eight records, and each
/// one is a single `write` of a whole line, so no line is ever interleaved with
/// another. The root directory is injectable so tests never touch the real one.
public actor HistoryStore {
    /// The file name inside the root directory.
    public static let fileName = "history.jsonl"

    /// The environment variable that moves the history somewhere else.
    ///
    /// It is read with `getenv` rather than through an injected dictionary so a
    /// test that sets it sees it take effect in the same process.
    public static let directoryVariable = "SPEECHKIT_HISTORY_DIR"

    /// The default root: `~/Library/Application Support/speechkit/`.
    public static var defaultRootDirectory: URL {
        if let override = getenv(directoryVariable).map({ String(cString: $0) }), !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("speechkit", isDirectory: true)
    }

    /// The directory holding the history file.
    public let root: URL

    /// The history file.
    public nonisolated var fileURL: URL {
        root.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    /// Creates a store.
    ///
    /// - Parameter root: The directory the history file lives in. Nothing is
    ///   created until the first append.
    public init(root: URL? = nil) {
        self.root = root ?? HistoryStore.defaultRootDirectory
    }

    /// A Boolean value indicating whether the history file exists.
    public var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Appends one record as one line.
    ///
    /// The directory is created with `0700` and the file with `0600` on first
    /// use, because the history names every file the machine has transcribed.
    ///
    /// - Throws: ``CLIError/writeFailed(_:reason:)`` when anything on the way
    ///   to the file fails.
    public func append(_ record: HistoryRecord) throws {
        var line = try encode(record)
        line.append(0x0A)

        let manager = FileManager.default
        do {
            if !manager.fileExists(atPath: root.path) {
                try manager.createDirectory(
                    at: root,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            }
            if !manager.fileExists(atPath: fileURL.path) {
                guard manager.createFile(
                    atPath: fileURL.path,
                    contents: nil,
                    attributes: [.posixPermissions: 0o600]
                ) else {
                    throw CLIError.writeFailed(fileURL, reason: "the file could not be created.")
                }
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            // One write per record, so two concurrent appends produce two whole
            // lines rather than one spliced one.
            try handle.write(contentsOf: line)
        } catch let error as CLIError {
            throw error
        } catch {
            throw CLIError.writeFailed(fileURL, reason: error.localizedDescription)
        }
    }

    /// Reads every record, skipping any line that does not decode.
    ///
    /// A truncated or hand-edited line costs its own row and nothing else: the
    /// count of skipped lines comes back so the caller can warn once.
    ///
    /// - Throws: ``CLIError/usage(_:)`` when the file exists but cannot be read.
    public func read() throws -> HistoryReadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw CLIError.usage("Could not read \(fileURL.path): \(error.localizedDescription)")
        }

        let decoder = HistoryRecord.decoder
        var records: [HistoryRecord] = []
        var skipped = 0
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            let trimmed = Data(line)
            guard !trimmed.isEmpty else { continue }
            if let record = try? decoder.decode(HistoryRecord.self, from: trimmed) {
                records.append(record)
            } else {
                skipped += 1
            }
        }
        return HistoryReadResult(records: records, skippedLines: skipped)
    }

    /// Deletes the history file.
    ///
    /// - Returns: `true` when a file was deleted, `false` when there was none.
    /// - Throws: ``CLIError/writeFailed(_:reason:)`` when the delete fails.
    @discardableResult
    public func clear() throws -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return false }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw CLIError.writeFailed(fileURL, reason: error.localizedDescription)
        }
        return true
    }

    private func encode(_ record: HistoryRecord) throws -> Data {
        do {
            return try HistoryRecord.encoder.encode(record)
        } catch {
            throw CLIError.writeFailed(fileURL, reason: error.localizedDescription)
        }
    }
}

/// The opt-out flag every recording command carries.
public struct HistoryOptions: ParsableArguments, Sendable {
    /// Records nothing for this run.
    @Flag(name: .long, help: "Do not record this run in the local usage history.")
    public var noHistory: Bool = false

    /// Creates empty options.
    public init() {}
}

/// Appends records without ever failing the run that produced them.
///
/// A history that cannot be written is a `--verbose` line, not an error: no one
/// should lose a transcript because a disk is full or a directory is read only.
public struct HistoryRecorder: Sendable {
    /// The environment variable that turns recording off.
    public static let disableVariable = "SPEECHKIT_NO_HISTORY"

    private let store: HistoryStore?
    private let console: Console

    /// A Boolean value indicating whether anything is recorded.
    public var isEnabled: Bool { store != nil }

    /// Creates a recorder around a store, or around nothing.
    public init(store: HistoryStore?, console: Console = Console()) {
        self.store = store
        self.console = console
    }

    /// Creates a recorder from the command flags and the environment.
    ///
    /// - Parameters:
    ///   - noHistory: The parsed `--no-history` flag.
    ///   - console: Where a failed append is reported, at `--verbose`.
    ///   - environment: The environment consulted for `SPEECHKIT_NO_HISTORY`.
    ///   - root: The history directory. Defaults to the real one.
    public init(
        noHistory: Bool,
        console: Console = Console(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        root: URL? = nil
    ) {
        let enabled = Self.isEnabled(noHistory: noHistory, environment: environment)
        self.store = enabled ? HistoryStore(root: root) : nil
        self.console = console
    }

    /// Returns whether a run with these flags and this environment records anything.
    ///
    /// The variable disables recording whatever it is set to, as long as it is
    /// not empty, because `SPEECHKIT_NO_HISTORY=0` in a shell profile is far
    /// more likely to mean "off" than "on".
    public static func isEnabled(noHistory: Bool, environment: [String: String]) -> Bool {
        if noHistory { return false }
        if let value = environment[disableVariable], !value.isEmpty { return false }
        return true
    }

    /// Records one run, or does nothing when recording is off.
    public func record(_ record: HistoryRecord) async {
        guard let store else { return }
        do {
            try await store.append(record)
        } catch {
            console.verbose("speechkit: could not record history: \(error.localizedDescription)")
        }
    }
}
