import ArgumentParser
import Foundation
import SpeechKit

/// A speech provider selectable with `--provider`.
public enum CLIProvider: String, CaseIterable, Sendable, ExpressibleByArgument, Codable {
    /// ElevenLabs Scribe.
    case elevenlabs
    /// Aqua Voice.
    case aqua
    /// Cohere.
    case cohere
    /// xAI Grok.
    case grok
    /// OpenAI.
    case openai
    /// Meta.
    case meta
    /// Google Gemini.
    case gemini
    /// Apple's local Speech framework.
    case apple

    /// Creates a provider from a case-insensitive argument.
    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }

    /// The values accepted by `--provider`.
    public static var allValueStrings: [String] {
        allCases.map(\.rawValue)
    }

    /// The matching SpeechKit file transcription provider.
    public var speechKitProvider: SpeechFileTranscriptionProvider {
        switch self {
        case .elevenlabs: return .elevenLabs
        case .aqua: return .aqua
        case .cohere: return .cohere
        case .grok: return .grok
        case .openai: return .openAI
        case .meta: return .meta
        case .gemini: return .gemini
        case .apple: return .apple
        }
    }

    /// The display name used in messages.
    public var displayName: String {
        switch self {
        case .elevenlabs: return "ElevenLabs"
        case .aqua: return "Aqua"
        case .cohere: return "Cohere"
        case .grok: return "Grok"
        case .openai: return "OpenAI"
        case .meta: return "Meta"
        case .gemini: return "Gemini"
        case .apple: return "Apple"
        }
    }
}
