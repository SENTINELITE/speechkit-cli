import Foundation

/// Creates the runner for a provider.
///
/// This switch is the only place providers are wired to runners. Runners added
/// in phase 2 validate `--model` and `--language` here, before any file is read,
/// so a bad value is a usage error rather than a per-file failure.
public enum ProviderRegistry {
    /// Returns a runner for a provider.
    ///
    /// - Throws: ``CLIError/invalidModel(provider:model:valid:)`` or
    ///   ``CLIError/invalidLanguage(provider:code:valid:)`` when the request does
    ///   not match the provider, or ``CLIError/appleUnavailable`` on operating
    ///   systems without Apple's local speech analyzer.
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
        case .gemini:
            let runner = GeminiRunner(context: context)
            try runner.validate()
            return runner
        case .meta:
            let runner = MetaRunner(context: context)
            try runner.validate()
            return runner
        case .elevenlabs:
            let runner = ElevenLabsRunner(context: context)
            try runner.validate()
            return runner
        case .aqua:
            let runner = AquaRunner(context: context)
            try runner.validate()
            return runner
        case .cohere:
            let runner = CohereRunner(context: context)
            try runner.validate()
            return runner
        }
    }
}
