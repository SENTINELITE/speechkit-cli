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
    /// The input file exists but cannot be read.
    case fileUnreadable(URL)
    /// The input file has an extension the provider does not accept.
    case unsupportedFileExtension(URL, accepted: [String])
    /// The input file is larger than the provider accepts.
    case fileTooLarge(URL, limit: Int64)
    /// Writing an output file failed.
    case writeFailed(URL, reason: String)
    /// Transcribing one input file failed.
    case transcriptionFailed(file: URL, reason: String)
    /// No credential was found for the provider.
    case missingCredential(CLIProvider)
    /// Every provider a benchmark was given lacked a credential.
    case noRunnableProviders([CLIProvider])
    /// Apple local transcription needs a newer operating system.
    case appleUnavailable
    /// An on-device model could not be downloaded or loaded.
    case modelNotReady(provider: CLIProvider, reason: String)
    /// An on-device model is missing and `--no-download` forbade fetching it.
    case modelDownloadRefused(provider: CLIProvider, size: String)
    /// A subtitle format was asked for but the transcript carries no timings.
    case noTimingData(provider: String)
    /// A subtitle format was asked for from a provider that never returns timings.
    case subtitlesUnsupported(provider: CLIProvider, formats: [String])
    /// A keychain operation failed.
    case keychainFailure(String)

    /// A localized description of the error.
    public var errorDescription: String? {
        switch self {
        case .usage(let message):
            return message
        case .missingProvider:
            return "No provider. Pass --provider or set SPEECHKIT_PROVIDER."
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
        case .fileUnreadable(let url):
            return "Cannot read \(url.path). Check the file permissions."
        case .unsupportedFileExtension(let url, let accepted):
            let name = url.pathExtension.isEmpty ? "no extension" : ".\(url.pathExtension.lowercased())"
            return "\(url.lastPathComponent) has \(name), which the provider does not accept. Accepted: \(accepted.map { ".\($0)" }.joined(separator: ", "))."
        case .fileTooLarge(let url, let limit):
            return "\(url.lastPathComponent) is larger than the provider limit of \(limit) bytes."
        case .writeFailed(let url, let reason):
            return "Failed to write \(url.path): \(reason)"
        case .transcriptionFailed(let file, let reason):
            return "\(file.lastPathComponent): \(reason)"
        case .missingCredential(let provider):
            let variable = CredentialResolver.environmentVariableName(for: provider)
            return "No credential for \(provider.rawValue). Pass --api-key or set \(variable)."
        case .noRunnableProviders(let providers):
            let names = providers.map(\.rawValue).sorted().joined(separator: ", ")
            let list = names.isEmpty ? "the providers named" : names
            return "No provider could run: no credential for \(list). Run 'speechkit providers' to see where each key is looked for."
        case .appleUnavailable:
            return "Apple local transcription requires macOS 26 or later."
        case .modelNotReady(let provider, let reason):
            return "The \(provider.rawValue) model is not ready: \(reason)"
        case .modelDownloadRefused(let provider, let size):
            return "The \(provider.rawValue) model is not downloaded, and --no-download was passed. Run 'speechkit \(provider.rawValue) prepare' to fetch it (\(size)), or drop --no-download."
        case .noTimingData(let provider):
            return "no timing data from \(provider); use --format txt or json, or pick a provider from 'speechkit providers' with segments"
        case .subtitlesUnsupported(let provider, let formats):
            let list = formats.map { "--format \($0)" }.joined(separator: " and ")
            return "\(provider.rawValue) never returns timing data, so \(list) cannot be written; use --format txt or json, or pick a provider from 'speechkit providers' with segments"
        case .keychainFailure(let reason):
            return reason
        }
    }

    /// The process exit code for the error.
    public var exitCode: Int32 {
        switch self {
        case .usage,
             .missingProvider,
             .unsupportedCapability,
             .invalidModel,
             .invalidLanguage,
             .fileNotFound,
             .inputIsDirectory,
             .fileUnreadable,
             .unsupportedFileExtension,
             .fileTooLarge,
             .noTimingData,
             .subtitlesUnsupported:
            return 1
        case .writeFailed, .transcriptionFailed:
            return 2
        case .missingCredential,
             .noRunnableProviders,
             .appleUnavailable,
             .modelNotReady,
             .modelDownloadRefused,
             .keychainFailure:
            return 3
        }
    }
}
