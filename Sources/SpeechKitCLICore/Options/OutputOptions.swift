import ArgumentParser
import Foundation

/// An output file format.
public enum OutputFormat: String, CaseIterable, Sendable, ExpressibleByArgument {
    /// Plain text.
    case txt
    /// A ``TranscriptDocument`` encoded as JSON.
    case json
    /// SubRip subtitles.
    case srt
    /// WebVTT subtitles.
    case vtt

    /// Creates a format from a case-insensitive argument.
    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }

    /// A Boolean value indicating whether the format needs segment timings.
    public var requiresTimings: Bool {
        self == .srt || self == .vtt
    }
}

/// How cues are built for subtitle formats.
public enum CueMode: String, CaseIterable, Sendable, ExpressibleByArgument {
    /// One cue per segment.
    case segments
    /// One cue per sentence, built from word timings.
    case sentences
    /// One cue per word.
    case words

    /// Creates a cue mode from a case-insensitive argument.
    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }
}

/// Where the tool writes transcripts.
public struct OutputOptions: ParsableArguments, Sendable {
    /// The formats to write. Repeat the flag to write several.
    @Option(name: [.customShort("f"), .long], help: "Output format: txt, json, srt, or vtt. Repeatable.")
    public var format: [OutputFormat] = []

    /// Where to write. A directory takes any number of inputs and formats; a
    /// file path takes one input and one format. Without it, output goes to stdout.
    @Option(
        name: [.customShort("o"), .long],
        help: "Write to this directory, or to this file when there is one input and one format. Without it, output goes to stdout."
    )
    public var output: String?

    /// Writes plain text as prose instead of one timestamped sentence per line.
    @Flag(name: .customLong("no-timestamps"), help: "Write txt as prose instead of one timestamped sentence per line.")
    public var noTimestamps: Bool = false

    /// Replaces existing output files instead of skipping them.
    @Flag(name: .long, help: "Replace existing output files.")
    public var overwrite: Bool = false

    /// Creates empty output options.
    public init() {}

    /// The requested formats, defaulting to plain text.
    public var resolvedFormats: [OutputFormat] {
        format.isEmpty ? [.txt] : format
    }

    /// Where transcripts go, resolved from `--output`.
    ///
    /// A path is a directory when it already exists as one or ends with a
    /// slash. Anything else is a single file path.
    public var target: OutputTarget {
        guard let output else { return .standardOutput }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: output, isDirectory: &isDirectory)
        if output.hasSuffix("/") || (exists && isDirectory.boolValue) {
            return .directory(URL(fileURLWithPath: output, isDirectory: true))
        }
        return .file(URL(fileURLWithPath: output))
    }
}

/// Where rendered transcripts go.
public enum OutputTarget: Sendable, Equatable {
    /// Standard output. The default.
    case standardOutput
    /// One file. Only valid with one input and one format.
    case file(URL)
    /// A directory holding `<input stem>.<format>` per input and format.
    case directory(URL)
}
