import Foundation

/// Creates the runner for a provider.
///
/// This switch is the only place providers are wired to runners, so later
/// phases add Gemini, Meta, ElevenLabs, Aqua, and Cohere here and nowhere else.
public enum ProviderRegistry {
    /// Returns a runner for a provider.
    ///
    /// - Throws: ``CLIError/notImplemented(_:)`` for providers a later phase adds,
    ///   or ``CLIError/appleUnavailable`` on operating systems without Apple's
    ///   local speech analyzer.
    public static func makeRunner(for provider: CLIProvider, context: RunContext) throws -> any ProviderRunner {
        switch provider {
        case .grok:
            return GrokRunner(context: context)
        case .openai:
            return OpenAIRunner(context: context)
        case .apple:
            if #available(macOS 26.0, *) {
                return AppleRunner(context: context)
            }
            throw CLIError.appleUnavailable
        case .elevenlabs, .aqua, .cohere, .meta, .gemini:
            throw CLIError.notImplemented("--provider \(provider.rawValue)")
        }
    }
}
