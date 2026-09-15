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

    /// A directory to write outputs into.
    @Option(name: [.customShort("o"), .long], help: "Write outputs into this directory.")
    public var outputDir: String?

    /// A single output path. Valid only with one input and one format.
    @Option(name: .long, help: "Write to this path. Only with one input file and one format.")
    public var output: String?

    /// Writes to standard output. Valid only with one input and one format.
    @Flag(name: .long, help: "Write to stdout. Only with one input file and one format.")
    public var stdout: Bool = false

    /// Replaces existing output files instead of skipping them.
    @Flag(name: .long, help: "Replace existing output files.")
    public var overwrite: Bool = false

    /// Creates empty output options.
    public init() {}

    /// The requested formats, defaulting to plain text.
    public var resolvedFormats: [OutputFormat] {
        format.isEmpty ? [.txt] : format
    }
}
