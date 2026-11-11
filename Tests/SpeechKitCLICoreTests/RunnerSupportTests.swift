import Foundation
import SpeechKit
import Testing
@testable import SpeechKitCLICore

@Suite("Runner support")
struct RunnerSupportTests {
    private func segment(_ text: String, _ start: Double, _ end: Double) -> TranscriptDocument.Segment {
        TranscriptDocument.Segment(start: start, end: end, text: text)
    }

    @Test("Segments come back in start order")
    func sorts() {
        let sorted = RunnerSupport.orderedSegments([
            segment("third", 2.5, 3),
            segment("first", 0, 1),
            segment("second", 1, 2),
        ])
        #expect(sorted.map(\.text) == ["first", "second", "third"])
    }

    @Test("Segments sharing a start keep the provider's order")
    func stable() {
        let sorted = RunnerSupport.orderedSegments([
            segment("a", 1, 2),
            segment("b", 1, 3),
            segment("c", 0, 1),
        ])
        #expect(sorted.map(\.text) == ["c", "a", "b"])
    }

    @Test("A segment that ends before it starts is dropped")
    func dropsImpossible() {
        let sorted = RunnerSupport.orderedSegments([
            segment("good", 0, 1),
            segment("backwards", 5, 4.9),
            segment("zero length", 2, 2),
        ])
        #expect(sorted.map(\.text) == ["good", "zero length"])
    }

    @Test("An empty list stays empty")
    func empty() {
        #expect(RunnerSupport.orderedSegments([]).isEmpty)
    }

    @Test("The model resolver falls back to the default and validates the rest")
    func resolveModel() throws {
        #expect(try RunnerSupport.resolveModel(nil, default: GrokModelID.stt, provider: .grok) == .stt)
        #expect(
            try RunnerSupport.resolveModel("grok-stt", default: GrokModelID.stt, provider: .grok) == .stt
        )
        let error = #expect(throws: CLIError.self) {
            _ = try RunnerSupport.resolveModel("bogus", default: GrokModelID.stt, provider: .grok)
        }
        #expect(error?.exitCode == 1)
        #expect(error?.localizedDescription.contains("grok-stt") == true)
    }

    @Test("A model outside the allowed list is rejected even when the enum has it")
    func resolveModelAllowedList() {
        let error = #expect(throws: CLIError.self) {
            _ = try RunnerSupport.resolveModel(
                ElevenLabsModelID.scribeV2Realtime.rawValue,
                default: ElevenLabsModelID.scribeV2,
                provider: .elevenlabs,
                allowed: ElevenLabsRunner.fileModelIDs
            )
        }
        #expect(error?.localizedDescription.contains("scribe_v3") == true)
    }

    @Test("Only the options that were passed produce a note")
    func droppedOptions() {
        #expect(RunnerSupport.droppedOptionWarnings(for: .aqua).isEmpty)
        #expect(RunnerSupport.droppedOptionWarnings(
            prompt: "a hint",
            keywords: ["SpeechKit"],
            timeout: 30,
            for: .cohere
        ) == [
            "SpeechKit's Cohere client takes no request timeout; --timeout was dropped.",
            "Cohere has no prompt parameter; --prompt was dropped.",
            "Cohere has no vocabulary parameter; --keyword was dropped.",
        ])
    }
}
