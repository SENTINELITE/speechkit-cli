import Foundation

/// Checks one input file against what a provider accepts, without reading it.
///
/// `transcribe` raises these as usage errors before the first upload, because a
/// run with one provider has nothing to salvage from a rejected file. `bench`
/// catches the same errors per file and records them as failed rows, because
/// Aqua's 25 MB limit should not abort the Gemini pass over the same folder.
public enum InputValidation {
    /// Checks that a file exists, is readable, and fits the provider's limits.
    ///
    /// - Parameters:
    ///   - url: The input file.
    ///   - capabilities: The provider's capability record. Tests pass a record
    ///     with a small byte limit to exercise the size check.
    /// - Throws: ``CLIError/fileNotFound(_:)``,
    ///   ``CLIError/inputIsDirectory(_:)``, ``CLIError/fileUnreadable(_:)``,
    ///   ``CLIError/unsupportedFileExtension(_:accepted:)``, or
    ///   ``CLIError/fileTooLarge(_:limit:)``.
    public static func check(_ url: URL, capabilities: ProviderCapabilities) throws {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw CLIError.fileNotFound(url)
        }
        if isDirectory.boolValue {
            throw CLIError.inputIsDirectory(url)
        }
        guard manager.isReadableFile(atPath: url.path) else {
            throw CLIError.fileUnreadable(url)
        }
        if let accepted = capabilities.acceptedExtensions {
            let extensionName = url.pathExtension.lowercased()
            guard accepted.contains(extensionName) else {
                throw CLIError.unsupportedFileExtension(url, accepted: accepted)
            }
        }
        if let limit = capabilities.maxFileBytes {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            if let size = values?.fileSize, Int64(size) > limit {
                throw CLIError.fileTooLarge(url, limit: limit)
            }
        }
    }
}
