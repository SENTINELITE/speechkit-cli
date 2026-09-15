import Foundation

/// Renders a transcript as WebVTT subtitles.
///
/// The file opens with `WEBVTT` and a `NOTE` block recording the provider, the
/// model, and the language. Times use a full stop before the milliseconds.
/// Speakers become `<v A>` voice spans when the transcript was produced with
/// `--diarize`. With word timings requested, cues carry inline timestamp tags
/// such as `<00:00:01.900>is`, which players use to highlight words as they are
/// spoken. The first word of a cue carries no tag, because the cue start
/// already covers it.
public struct VTTFormatter: TranscriptFormatter {
    /// A Boolean value indicating whether `<v A>` voice spans are written.
    public let showSpeakers: Bool

    /// A Boolean value indicating whether inline word timing tags are written.
    public let showWordTimings: Bool

    /// The cue builder whose line width wraps the cue text.
    public let cueBuilder: CueBuilder

    /// The `vtt` file extension.
    public let fileExtension = "vtt"

    /// The tolerance, in seconds, for deciding a word belongs to a cue.
    ///
    /// A word must start inside the cue, so the word that starts exactly where
    /// the cue ends belongs to the next cue. That is what keeps `--cues words`
    /// free of inline tags: a one-word cue never picks up its neighbour.
    private static let matchTolerance: Double = 0.001

    /// Creates a WebVTT formatter.
    ///
    /// - Parameters:
    ///   - showSpeakers: Whether to write voice spans.
    ///   - showWordTimings: Whether to write inline word timing tags.
    ///   - cueBuilder: The builder that supplies the line width.
    public init(
        showSpeakers: Bool = false,
        showWordTimings: Bool = false,
        cueBuilder: CueBuilder = CueBuilder()
    ) {
        self.showSpeakers = showSpeakers
        self.showWordTimings = showWordTimings
        self.cueBuilder = cueBuilder
    }

    /// Renders the document as WebVTT subtitles.
    ///
    /// - Throws: ``CLIError/noTimingData(provider:)`` when the transcript has no
    ///   timed segments, because subtitles are never guessed.
    public func render(_ document: TranscriptDocument) throws -> String {
        guard document.hasTimings else {
            throw CLIError.noTimingData(provider: document.provider)
        }

        let labels = SpeakerLabels.labels(in: document.segments)
        var blocks: [String] = ["WEBVTT", note(for: document)]
        var cues: [String] = []

        for (index, segment) in document.segments.enumerated() {
            let text = Self.escaped(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !text.isEmpty else { continue }
            let timing = TimecodeFormatter.range(start: segment.start, end: segment.end, style: .vtt)
            let prefix = showSpeakers ? (labels[index].map { "<v \($0)>" } ?? "") : ""

            let body: String
            if let tagged = taggedBody(for: segment, words: document.words) {
                body = prefix + tagged
            } else {
                let lines = cueBuilder.wrapLines(prefix + text)
                body = lines.joined(separator: "\n")
            }
            guard !body.isEmpty else { continue }
            cues.append("\(timing)\n\(body)")
        }

        guard !cues.isEmpty else {
            throw CLIError.noTimingData(provider: document.provider)
        }
        blocks.append(contentsOf: cues)
        return blocks.joined(separator: "\n\n") + "\n"
    }

    /// Returns the `NOTE` block naming the provider, model, and language.
    ///
    /// A `NOTE` block runs until the next blank line, and `-->` inside one would
    /// read as a cue timing, so both are taken out of the values.
    private func note(for document: TranscriptDocument) -> String {
        var lines = ["NOTE", "provider: \(Self.sanitizedNote(document.provider))"]
        if let model = document.model {
            lines.append("model: \(Self.sanitizedNote(model))")
        }
        if let language = document.language {
            lines.append("language: \(Self.sanitizedNote(language))")
        }
        return lines.joined(separator: "\n")
    }

    /// Returns cue text with the three characters WebVTT reads as markup escaped.
    ///
    /// This runs before the voice span and the inline timing tags are added, so
    /// `AT&T` and `<inaudible>` reach the player as text while `<v A>` and
    /// `<00:00:01.900>` stay markup.
    static func escaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Returns a `NOTE` value with line breaks and cue arrows removed.
    static func sanitizedNote(_ text: String) -> String {
        text
            .replacingOccurrences(of: "-->", with: "--")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Returns the cue body with inline word timing tags, or `nil` when the cue
    /// has no usable word timings and should be rendered as plain wrapped text.
    private func taggedBody(
        for segment: TranscriptDocument.Segment,
        words: [TranscriptDocument.Word]
    ) -> String? {
        guard showWordTimings, !words.isEmpty else { return nil }
        let inside = words.filter { word in
            guard let start = word.start else { return false }
            return start >= segment.start - Self.matchTolerance
                && start < segment.end - Self.matchTolerance
        }
        guard inside.count > 1 else { return nil }

        var pieces: [String] = []
        for (index, word) in inside.enumerated() {
            let text = Self.escaped(word.text.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !text.isEmpty else { continue }
            guard index > 0, let start = word.start else {
                pieces.append(text)
                continue
            }
            pieces.append("<\(TimecodeFormatter.timecode(start, style: .vtt))>\(text)")
        }
        guard pieces.count > 1 else { return nil }
        return pieces.joined(separator: " ")
    }
}
