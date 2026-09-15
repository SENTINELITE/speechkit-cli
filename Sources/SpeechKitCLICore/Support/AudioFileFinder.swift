import Foundation

/// Turns the positional arguments of `bench` into a list of audio files.
///
/// `transcribe` refuses a directory and points at a shell glob, because one
/// mistyped path there is worth stopping for. `bench` is pointed at a folder on
/// purpose, so a directory expands to the audio files in it.
public enum AudioFileFinder {
    /// The extensions a directory contributes.
    ///
    /// A file named on the command line is taken whatever it is called, so this
    /// list only decides what a folder sweep picks up. It is the union of what
    /// the providers accept, not what any one of them does; the per-provider
    /// extension check still runs and still records a failed row.
    public static let audioExtensions: Set<String> = [
        "wav", "mp3", "m4a", "aac", "flac", "ogg", "opus", "mp4", "webm", "aiff", "aif", "caf"
    ]

    /// Returns the audio files named by the arguments, in order.
    ///
    /// A path that is a directory contributes its audio files, sorted by name.
    /// Anything else is taken as given, including a path that does not exist:
    /// the per-provider check turns that into a failed row naming the file,
    /// which is more use in a comparison than aborting the run.
    ///
    /// - Parameters:
    ///   - paths: The positional arguments.
    ///   - recursive: Whether a directory is walked into its subdirectories.
    /// - Returns: The files, deduplicated, in argument order.
    public static func expand(_ paths: [String], recursive: Bool) -> [URL] {
        var found: [URL] = []
        var seen: Set<String> = []

        for path in paths {
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            let candidates = exists && isDirectory.boolValue
                ? audioFiles(in: url, recursive: recursive)
                : [url]
            for candidate in candidates where seen.insert(candidate.standardizedFileURL.path).inserted {
                found.append(candidate)
            }
        }
        return found
    }

    /// Returns the audio files in a directory, sorted by name.
    ///
    /// Hidden entries are skipped, so a `.DS_Store` or a `.git` directory never
    /// reaches a provider, and subdirectories are descended into only when
    /// `recursive` is set.
    public static func audioFiles(in directory: URL, recursive: Bool) -> [URL] {
        let manager = FileManager.default
        let entries = (try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var files: [URL] = []
        var subdirectories: [URL] = []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard !entry.lastPathComponent.hasPrefix(".") else { continue }
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: entry.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                subdirectories.append(entry)
            } else if audioExtensions.contains(entry.pathExtension.lowercased()) {
                files.append(entry)
            }
        }

        guard recursive else { return files }
        // The directory's own files come before its subdirectories', so a sweep
        // reads in the order the folder looks on screen.
        return files + subdirectories.flatMap { audioFiles(in: $0, recursive: true) }
    }
}
