import Foundation
import SpeechKit
import SpeechKitVoz

enum FailureMessage {
    static func message(for error: Error) -> String {
        if let cli = error as? CLIError { return cli.localizedDescription }
        if let message = providerMessage(for: error) { return message }
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            return SpeechFailure(.cancelled).localizedDescription
        }
        if (error as? URLError)?.code == .timedOut {
            return "The request failed: \(SpeechFailureReason.timedOut)."
        }
        return SpeechFailure(.transport).localizedDescription
    }

    static func providerMessage(for error: Error) -> String? {
        if let failure = error as? SpeechFailure {
            let status = failure.statusCode.map { " (HTTP \($0))" } ?? ""
            return "\(failure.category.rawValue)\(status): \(failure.localizedDescription)"
        }
        if let speech = error as? SpeechError {
            switch speech {
            case .unsupportedCapability(let provider, _):
                return "\(provider.rawValue) does not support the requested capability."
            case .appleSpeechUnsupportedLocale:
                return "Apple local speech transcription does not support the requested locale."
            case .appleSpeechAssetsUnavailable:
                return "Apple local speech assets for the requested locale are not installed."
            default:
                return speech.localizedDescription
            }
        }
        if error is ElevenLabsError || error is OpenAIError || error is FishAudioRealtimeError ||
            error is GrokRealtimeError || error is MetaRealtimeError || error is GeminiRealtimeError ||
            error is MistralRealtimeError {
            return (error as? LocalizedError)?.errorDescription
        }
        if let voz = error as? VozError {
            switch voz {
            case .downloadFailed: return "Downloading the VOZ model failed."
            case .loadFailed: return "Loading the VOZ model failed."
            case .transcriptionFailed: return "VOZ transcription failed."
            default: return voz.localizedDescription
            }
        }
        return nil
    }
}
