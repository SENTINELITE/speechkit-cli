import Foundation

/// Compares a transcript against a reference transcript, word by word.
///
/// The measure is the usual one: the Levenshtein distance between the two word
/// sequences, divided by the number of words in the reference. `0` is a perfect
/// match and values above `1` are possible, because a transcript can be longer
/// than the reference it is scored against.
///
/// Normalisation is deliberately shallow. Case and punctuation are ignored,
/// because no provider agrees on them, but nothing else is expanded: "twenty
/// five" and "25" stay different words, and so do "doctor" and "Dr". Anything
/// cleverer would be a judgement about the reference rather than a measurement
/// of the transcript.
public enum WordErrorRate {
    /// Returns the comparable words of a transcript.
    ///
    /// Text is lowercased, every character that is not a letter, a digit, or an
    /// apostrophe becomes a separator, and apostrophes survive only inside a
    /// word, so `don't` keeps its apostrophe and `'quoted'` loses both.
    /// Typographic apostrophes are folded onto the ASCII one first, so a
    /// provider that writes `don\u{2019}t` is not punished for it.
    ///
    /// - Parameter text: The transcript text.
    /// - Returns: The words, in order.
    public static func words(in text: String) -> [String] {
        var tokens: [String] = []
        var current = ""

        func flush() {
            // Apostrophes are kept only between two kept characters, so the
            // trimming happens here rather than in the scan.
            var word = current
            while word.hasPrefix("'") { word.removeFirst() }
            while word.hasSuffix("'") { word.removeLast() }
            if !word.isEmpty { tokens.append(word) }
            current = ""
        }

        for character in text.lowercased() {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if character == "'" || character == "\u{2019}" {
                current.append("'")
            } else {
                flush()
            }
        }
        flush()
        return tokens
    }

    /// Returns the word error rate of a transcript against a reference.
    ///
    /// - Parameters:
    ///   - reference: The reference transcript, as the user wrote it.
    ///   - hypothesis: The transcript a provider produced.
    /// - Returns: The rate, or `nil` when the reference holds no words, which
    ///   is reported as a blank cell rather than a division by zero.
    public static func rate(reference: String, hypothesis: String) -> Double? {
        rate(reference: words(in: reference), hypothesis: words(in: hypothesis))
    }

    /// Returns the word error rate of two already-normalised word sequences.
    ///
    /// - Parameters:
    ///   - reference: The reference words.
    ///   - hypothesis: The transcript words.
    /// - Returns: The rate, or `nil` when the reference is empty.
    public static func rate(reference: [String], hypothesis: [String]) -> Double? {
        guard !reference.isEmpty else { return nil }
        return Double(distance(reference, hypothesis)) / Double(reference.count)
    }

    /// Returns the word-level Levenshtein distance between two sequences.
    ///
    /// Substitutions, insertions, and deletions all cost one. Only two rows of
    /// the matrix are kept, so a long file costs memory proportional to the
    /// shorter side rather than to their product.
    public static func distance(_ reference: [String], _ hypothesis: [String]) -> Int {
        if reference.isEmpty { return hypothesis.count }
        if hypothesis.isEmpty { return reference.count }

        var previous = Array(0...hypothesis.count)
        var current = [Int](repeating: 0, count: hypothesis.count + 1)

        for (rowIndex, referenceWord) in reference.enumerated() {
            current[0] = rowIndex + 1
            for (columnIndex, hypothesisWord) in hypothesis.enumerated() {
                let substitution = previous[columnIndex] + (referenceWord == hypothesisWord ? 0 : 1)
                let deletion = previous[columnIndex + 1] + 1
                let insertion = current[columnIndex] + 1
                current[columnIndex + 1] = min(substitution, deletion, insertion)
            }
            swap(&previous, &current)
        }
        return previous[hypothesis.count]
    }

    /// Returns the reference text for an input file, when one exists.
    ///
    /// With `--reference-dir`, the reference is `<stem>.txt` in that directory.
    /// Without it, a `<stem>.reference.txt` beside the input counts, so a folder
    /// can carry its own answers.
    ///
    /// - Parameters:
    ///   - input: The audio file.
    ///   - directory: The `--reference-dir` value, when it was passed.
    /// - Returns: The reference text, or `nil` when there is no reference file
    ///   or it cannot be read.
    public static func referenceText(for input: URL, directory: URL?) -> String? {
        let stem = input.deletingPathExtension().lastPathComponent
        let candidate: URL
        if let directory {
            candidate = directory.appendingPathComponent(stem).appendingPathExtension("txt")
        } else {
            candidate = input.deletingLastPathComponent()
                .appendingPathComponent("\(stem).reference.txt")
        }
        return try? String(contentsOf: candidate, encoding: .utf8)
    }
}
