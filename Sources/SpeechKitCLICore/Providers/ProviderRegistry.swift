import Foundation

/// Creates the runner for a provider.
///
/// This switch is the only place providers are wired to runners. Every runner
/// validates its `--model`, `--language`, and flag combinations here, before any
/// file is read, so a bad value is a usage error rather than a per-file failure.
public enum ProviderRegistry {
    /// Returns a validated runner for a provider.
    ///
    /// - Throws: ``CLIError/invalidModel(provider:model:valid:)``,
    ///   ``CLIError/invalidLanguage(provider:code:valid:)``, or
    ///   ``CLIError/usage(_:)`` when the request does not match the provider, or
    ///   ``CLIError/appleUnavailable`` on operating systems without Apple's
    ///   local speech analyzer.
    public static func makeRunner(for provider: CLIProvider, context: RunContext) async throws -> any ProviderRunner {
        let runner: any ProviderRunner
        switch provider {
        case .grok:
            runner = GrokRunner(context: context)
        case .openai:
            runner = OpenAIRunner(context: context)
        case .apple:
            guard #available(macOS 26.0, *) else {
                throw CLIError.appleUnavailable
            }
            runner = AppleRunner(context: context)
        case .gemini:
            runner = GeminiRunner(context: context)
        case .meta:
            runner = MetaRunner(context: context)
        case .elevenlabs:
            runner = ElevenLabsRunner(context: context)
        case .aqua:
            runner = AquaRunner(context: context)
        case .cohere:
            runner = CohereRunner(context: context)
        }
        try await runner.validate()
        return runner
    }
}
