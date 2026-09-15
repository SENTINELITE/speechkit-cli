import Foundation

/// Synthesises the short clip `keys check --live` sends to every provider.
///
/// The repository carries no media fixtures, so the clip is spoken by `say` and
/// re-encoded by `afconvert` into 16 kHz mono WAV, the one encoding every
/// provider accepts. The clip is built once per run and reused for every
/// provider, so a check of nine providers still costs one synthesis.
public enum ProbeAudio: Sendable {
    /// The phrase the probe clip speaks.
    public static let phrase = "Testing one two three"

    /// The `say` binary.
    static let sayPath = "/usr/bin/say"

    /// The `afconvert` binary.
    static let afconvertPath = "/usr/bin/afconvert"

    /// A generated probe clip and the temporary directory holding it.
    ///
    /// The directory is the unit of cleanup because `say` writes an AIFF beside
    /// the WAV, and both should go when the check finishes.
    public struct Clip: Sendable {
        /// The 16 kHz mono WAV file.
        public let url: URL
        /// The temporary directory holding the clip.
        public let directory: URL

        /// Creates a clip handle.
        public init(url: URL, directory: URL) {
            self.url = url
            self.directory = directory
        }

        /// Deletes the directory and everything in it.
        public func remove() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// Speaks `phrase` into a fresh 16 kHz mono WAV file.
    ///
    /// - Parameters:
    ///   - phrase: The words to speak. Defaults to ``phrase``.
    ///   - directory: Where to build the clip. Defaults to a new directory
    ///     under the system temporary directory.
    /// - Returns: The generated clip, which the caller removes when done.
    /// - Throws: ``CLIError/usage(_:)`` when `say` or `afconvert` is missing or
    ///   fails, or when the temporary directory cannot be created.
    public static func make(
        phrase: String = ProbeAudio.phrase,
        in directory: URL? = nil
    ) throws -> Clip {
        try requireTools()

        let folder = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("speechkit-probe-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw CLIError.usage("Could not create a temporary directory for the probe clip: \(error.localizedDescription)")
        }

        let aiff = folder.appendingPathComponent("probe.aiff")
        let wav = folder.appendingPathComponent("probe.wav")
        try run(sayPath, ["-o", aiff.path, phrase])
        try run(afconvertPath, ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", aiff.path, wav.path])

        guard FileManager.default.isReadableFile(atPath: wav.path) else {
            throw CLIError.usage("The probe clip was not written to \(wav.path).")
        }
        return Clip(url: wav, directory: folder)
    }

    /// Checks that both command line tools exist before either is run.
    ///
    /// - Throws: ``CLIError/usage(_:)`` naming the missing tool.
    static func requireTools() throws {
        for tool in [sayPath, afconvertPath] where !FileManager.default.isExecutableFile(atPath: tool) {
            throw CLIError.usage(
                "\(tool) is missing, so the probe clip cannot be generated. "
                    + "'keys check --live' needs both \(sayPath) and \(afconvertPath)."
            )
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors

        do {
            try process.run()
        } catch {
            throw CLIError.usage("Could not run \(tool): \(error.localizedDescription)")
        }
        let output = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let detail = String(decoding: output, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = detail.isEmpty ? "" : ": \(detail)"
            throw CLIError.usage("\(tool) exited with status \(process.terminationStatus)\(suffix)")
        }
    }
}
