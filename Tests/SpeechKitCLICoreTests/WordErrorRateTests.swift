import Foundation
import Testing
@testable import SpeechKitCLICore

@Suite("Word error rate")
struct WordErrorRateTests {
    @Test("An identical transcript scores zero")
    func identity() {
        #expect(WordErrorRate.rate(
            reference: "the quick brown fox",
            hypothesis: "the quick brown fox"
        ) == 0)
    }

    @Test("One substitution in four words scores a quarter")
    func substitution() {
        #expect(WordErrorRate.rate(
            reference: "the quick brown fox",
            hypothesis: "the quick brown dog"
        ) == 0.25)
    }

    @Test("One inserted word scores a quarter")
    func insertion() {
        #expect(WordErrorRate.rate(
            reference: "the quick brown fox",
            hypothesis: "the very quick brown fox"
        ) == 0.25)
    }

    @Test("One missing word scores a quarter")
    func deletion() {
        #expect(WordErrorRate.rate(
            reference: "the quick brown fox",
            hypothesis: "the quick fox"
        ) == 0.25)
    }

    @Test("A transcript longer than the reference can score above one")
    func aboveOne() {
        let rate = WordErrorRate.rate(reference: "one two", hypothesis: "a b c d e f")
        #expect(rate == 3)
    }

    @Test("An empty reference is blank rather than a crash")
    func emptyReference() {
        #expect(WordErrorRate.rate(reference: "", hypothesis: "anything at all") == nil)
        #expect(WordErrorRate.rate(reference: "  ...  ", hypothesis: "anything") == nil)
        #expect(WordErrorRate.rate(reference: "a word", hypothesis: "") == 1)
    }

    @Test("Case and punctuation are ignored")
    func normalisation() {
        #expect(WordErrorRate.rate(
            reference: "The quick, brown fox!",
            hypothesis: "the QUICK brown fox."
        ) == 0)
    }

    @Test("An apostrophe inside a word is kept and one around a word is not")
    func apostrophes() {
        #expect(WordErrorRate.words(in: "Don't 'quote' me \u{2019}kay") == ["don't", "quote", "me", "kay"])
        #expect(WordErrorRate.rate(reference: "don't stop", hypothesis: "don\u{2019}t stop") == 0)
    }

    @Test("Whitespace of any shape collapses")
    func whitespace() {
        #expect(WordErrorRate.words(in: "  one\n\ttwo   three \n") == ["one", "two", "three"])
    }

    @Test("Nothing beyond case and punctuation is expanded")
    func noExpansion() {
        #expect(WordErrorRate.rate(reference: "twenty five", hypothesis: "25") == 1)
    }

    @Test("A reference file is found in the reference directory")
    func referenceDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("speechkit-wer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try "spoken words".write(
            to: directory.appendingPathComponent("talk.txt"),
            atomically: true,
            encoding: .utf8
        )
        let input = directory.appendingPathComponent("talk.wav")
        #expect(WordErrorRate.referenceText(for: input, directory: directory) == "spoken words")
        #expect(WordErrorRate.referenceText(for: input, directory: nil) == nil)

        try "beside it".write(
            to: directory.appendingPathComponent("talk.reference.txt"),
            atomically: true,
            encoding: .utf8
        )
        #expect(WordErrorRate.referenceText(for: input, directory: nil) == "beside it")
    }
}
