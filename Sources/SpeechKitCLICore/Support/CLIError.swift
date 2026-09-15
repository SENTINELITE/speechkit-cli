import Foundation

/// An error raised by the command-line tool.
///
/// Each case maps to one of the documented process exit codes: `1` for a usage
/// or configuration problem found before any work, `2` when at least one file
/// failed while others succeeded, and `3` when a credential is missing or the
/// provider is not usable on this machine.
public enum CLIError: Error, LocalizedError, Sendable, Equatable {
    /// A usage problem, such as conflicting flags.
    case usage(String)
    /// No provider was given on the command line or in the environment.
    case missingProvider
    /// A feature that a later phase implements was requested.
    case notImplemented(String)
    /// The provider cannot do what the flags asked for.
    case unsupportedCapability(provider: CLIProvider, capability: String)
    /// The model identifier is not one the provider accepts.
    case invalidModel(provider: CLIProvider, model: String, valid: [String])
    /// The language code is not one the provider accepts.
    case invalidLanguage(provider: CLIProvider, code: String, valid: [String])
    /// The input path does not exist.
    case fileNotFound(URL)
    /// The input path is a directory.
    case inputIsDirectory(URL)
    /// The input file is larger than the provider accepts.
    case fileTooLarge(URL, limit: Int64)
    /// An output file exists and `--overwrite` was not passed.
    case outputExists(URL)
    /// Writing an output file failed.
    case writeFailed(URL, reason: String)
    /// Transcribing one input file failed.
    case transcriptionFailed(file: URL, reason: String)
    /// No credential was found for the provider.
    case missingCredential(CLIProvider)
    /// Apple local transcription needs a newer operating system.
    case appleUnavailable

    /// A localized description of the error.
    public var errorDescription: String? {
        switch self {
        case .usage(let message):
            return message
        case .missingProvider:
            return "No provider. Pass --provider or set SPEECHKIT_PROVIDER."
        case .notImplemented(let what):
            return "\(what) is not implemented in this phase."
        case .unsupportedCapability(let provider, let capability):
            return "\(provider.rawValue) does not support \(capability)."
        case .invalidModel(let provider, let model, let valid):
            return "\(model) is not a \(provider.rawValue) model. Valid values: \(valid.joined(separator: ", "))."
        case .invalidLanguage(let provider, let code, let valid):
            if valid.isEmpty {
                return "\(provider.rawValue) does not accept the language \(code)."
            }
            return "\(provider.rawValue) does not accept the language \(code). Valid values: \(valid.joined(separator: ", "))."
        case .fileNotFound(let url):
            return "No such file: \(url.path)"
        case .inputIsDirectory(let url):
            return "\(url.path) is a directory. Pass files, or use a shell glob."
        case .fileTooLarge(let url, let limit):
            return "\(url.lastPathComponent) is larger than the provider limit of \(limit) bytes."
        case .outputExists(let url):
            return "\(url.path) exists. Pass --overwrite to replace it."
        case .writeFailed(let url, let reason):
            return "Failed to write \(url.path): \(reason)"
        case .transcriptionFailed(let file, let reason):
            return "\(file.lastPathComponent): \(reason)"
        case .missingCredential(let provider):
            let variable = CredentialResolver.environmentVariableName(for: provider)
            return "No credential for \(provider.rawValue). Pass --api-key or set \(variable)."
        case .appleUnavailable:
            return "Apple local transcription requires macOS 26 or later."
        }
    }

    /// The process exit code for the error.
    public var exitCode: Int32 {
        switch self {
        case .usage,
             .missingProvider,
             .notImplemented,
             .unsupportedCapability,
             .invalidModel,
             .invalidLanguage,
             .fileNotFound,
             .inputIsDirectory,
             .fileTooLarge,
             .outputExists:
            return 1
        case .writeFailed, .transcriptionFailed:
            return 2
        case .missingCredential, .appleUnavailable:
            return 3
        }
    }
}
