import Foundation
import SpeechKit
import SpeechKitVoz
import Testing
@testable import SpeechKitCLICore

@Suite("Safe failure messages")
struct FailureMessageTests {
    @Test("Transport failures retain only their category and status", arguments: [
        SpeechFailure.Category.invalidEndpoint, .redirectRefused, .invalidCredential,
        .unsupportedAuthentication, .credentialResolution, .transport, .cancelled,
        .invalidResponse, .server, .staticKeysDisallowed, .attestationUnsupported,
        .attestationFailed, .pinningFailed
    ])
    func categories(_ category: SpeechFailure.Category) {
        let message = FailureMessage.message(for: SpeechFailure(category, statusCode: 401))
        #expect(message.contains(category.rawValue))
        #expect(message.contains("HTTP 401"))
        #expect(Bench.message(for: SpeechFailure(category, statusCode: 401)) == message)
    }

    @Test("Provider reasons are bounded categories", arguments: [
        SpeechFailureReason.requestFailed, .invalidOptions, .invalidResponse, .uploadFailed,
        .decodingFailed, .timedOut, .sessionEnding
    ])
    func reasons(_ reason: SpeechFailureReason) {
        let errors: [any Error] = [
            SpeechError.providerFailure(provider: .openAI, reason: reason),
            SpeechError.uploadFailed(provider: .gemini, reason: reason),
            SpeechError.decodingFailed(provider: .fishAudio, reason: reason),
            OpenAIError.invalidOptions(reason), ElevenLabsError.uploadFailed(reason)
        ]
        for error in errors {
            #expect(FailureMessage.message(for: error).contains(reason.rawValue))
        }
    }

    @Test("HTTP and Fish Audio errors preserve safe codes")
    func statusCodes() {
        #expect(FailureMessage.message(for: SpeechError.httpFailure(provider: .fishAudio, statusCode: 429)).contains("429"))
        #expect(FailureMessage.message(for: FishAudioRealtimeError.serverError(code: 503)).contains("503"))
        #expect(!FailureMessage.message(for: FishAudioRealtimeError.sessionClosed(code: 4500)).isEmpty)
    }

    @Test("Unknown errors and VOZ details cannot echo a secret")
    func untrustedDescriptions() {
        let secret = "synthetic-secret-do-not-print"
        let errors: [any Error] = [
            NSError(domain: secret, code: 1, userInfo: [NSLocalizedDescriptionKey: secret]),
            URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: secret]),
            VozError.downloadFailed(secret), VozError.loadFailed(secret), VozError.transcriptionFailed(secret),
            SpeechError.unsupportedCapability(provider: .openAI, capability: secret),
            SpeechError.appleSpeechUnsupportedLocale(localeIdentifier: secret)
        ]
        for error in errors {
            #expect(!FailureMessage.message(for: error).contains(secret))
            #expect(!Bench.message(for: error).contains(secret))
            #expect(!VozModelSession.message(for: error).contains(secret))
        }
    }

    @Test("Cancellation and timeouts remain recognizable")
    func cancellationAndTimeout() {
        #expect(FailureMessage.message(for: CancellationError()).contains("cancelled"))
        #expect(FailureMessage.message(for: URLError(.cancelled)).contains("cancelled"))
        #expect(FailureMessage.message(for: URLError(.timedOut)).contains("timedOut"))
    }

    @Test("Transcription failures use the safe formatter before recording")
    func transcriptionBoundary() async throws {
        let command = try Transcribe.parse(["test.wav", "-p", "openai", "--no-history"])
        let console = Console(verbosity: .quiet)
        let file = URL(fileURLWithPath: "/tmp/test.wav")
        let outcome = await command.run(
            file: file, index: 1, total: 1, provider: .openai,
            runner: FailingRunner(context: RunContext()),
            writer: OutputWriter(target: .standardOutput, overwrite: false, console: console),
            console: console
        )
        #expect(outcome.failure == .transcriptionFailed(file: file, reason: "The connection failed."))
    }

    private struct FailingRunner: ProviderRunner {
        static let provider = CLIProvider.openai
        init(context: RunContext) {}
        func transcribe(file: URL) async throws -> TranscriptDocument {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "synthetic-secret-do-not-print"])
        }
    }
}
