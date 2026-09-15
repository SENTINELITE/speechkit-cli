import Foundation
import SpeechKit
import Testing
@testable import SpeechKitCLICore

/// How `--model`, `--words`, `--diarize`, and `--prompt` are reconciled for OpenAI.
///
/// SpeechKit refuses several of these combinations, so every case here is one
/// the CLI has to settle before an upload starts.
@Suite("OpenAI options")
struct OpenAIOptionsTests {
    private func resolve(
        model: String? = nil,
        words: Bool = false,
        diarize: Bool = false,
        prompt: String? = nil
    ) throws -> OpenAIRunner.ResolvedOptions {
        try OpenAIRunner.resolveOptions(
            model: model,
            wantsWords: words,
            wantsDiarization: diarize,
            prompt: prompt
        )
    }

    @Test("Without flags the default model is unchanged and no granularities are sent")
    func defaults() throws {
        let resolved = try resolve()
        #expect(resolved.modelID == .gptTranscribe)
        #expect(resolved.timestampGranularities.isEmpty)
        #expect(resolved.diarizes == false)
        #expect(resolved.warnings.isEmpty)
    }

    @Test("--words with no --model flips the default to whisper-1")
    func wordsFlipsDefault() throws {
        let resolved = try resolve(words: true)
        #expect(resolved.modelID == .whisper1)
        #expect(resolved.timestampGranularities == [.word, .segment])
        #expect(resolved.prompt == nil)
    }

    @Test("--words with an explicit non-whisper model is a usage error")
    func wordsWithExplicitModel() {
        for model in ["gpt-transcribe", "gpt-4o-transcribe", "gpt-4o-mini-transcribe"] {
            let error = #expect(throws: CLIError.self) {
                _ = try resolve(model: model, words: true)
            }
            #expect(error?.exitCode == 1)
            #expect(error?.localizedDescription.contains("whisper-1") == true)
        }
        #expect(throws: Never.self) {
            _ = try resolve(model: "whisper-1", words: true)
        }
    }

    @Test("--diarize with no --model selects the diarizing model and its chunking strategy")
    func diarizeSelectsModel() throws {
        let resolved = try resolve(diarize: true)
        #expect(resolved.modelID == .gpt4oTranscribeDiarize)
        #expect(resolved.diarizes)
        #expect(resolved.diarizationChunkingStrategy != nil)
        #expect(resolved.timestampGranularities.isEmpty)
    }

    @Test("--diarize with an explicit non-diarize model is a usage error")
    func diarizeWithExplicitModel() {
        let error = #expect(throws: CLIError.self) {
            _ = try resolve(model: "gpt-transcribe", diarize: true)
        }
        #expect(error?.exitCode == 1)
        #expect(error?.localizedDescription.contains("gpt-4o-transcribe-diarize") == true)
    }

    @Test("The diarizing model drops --prompt with a note and sends no granularities")
    func diarizeModelDropsPrompt() throws {
        let resolved = try resolve(model: "gpt-4o-transcribe-diarize", words: true, prompt: "a hint")
        #expect(resolved.prompt == nil)
        #expect(resolved.timestampGranularities.isEmpty)
        #expect(resolved.warnings.count == 2)
        #expect(resolved.warnings[0].contains("--prompt"))
        #expect(resolved.warnings[1].contains("--words"))
    }

    @Test("A chunking strategy is sent only under the diarizing model")
    func chunkingStrategyOnlyWhenDiarizing() throws {
        #expect(try resolve(model: "whisper-1").diarizationChunkingStrategy == nil)
        #expect(try resolve(model: "gpt-4o-transcribe-diarize").diarizationChunkingStrategy != nil)
    }

    @Test("A prompt survives on the models that accept one")
    func promptSurvives() throws {
        #expect(try resolve(prompt: "a hint").prompt == "a hint")
    }

    @Test("--words and --diarize together are refused rather than silently reduced")
    func wordsAndDiarize() {
        let error = #expect(throws: CLIError.self) {
            _ = try resolve(words: true, diarize: true)
        }
        #expect(error?.exitCode == 1)
    }

    @Test("An unknown model is still rejected with the valid list")
    func unknownModel() {
        let error = #expect(throws: CLIError.self) {
            _ = try resolve(model: "bogus")
        }
        #expect(error?.localizedDescription.contains("whisper-1") == true)
    }

    @Test("The runner validates before the credential is ever used")
    func runnerValidates() async {
        let context = RunContext(credential: .apiKey("key"), model: "gpt-transcribe", wantsWords: true)
        await #expect(throws: CLIError.self) {
            _ = try await ProviderRegistry.makeRunner(for: .openai, context: context)
        }
    }
}
