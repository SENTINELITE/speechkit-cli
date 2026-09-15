import AVFoundation
import Foundation

/// Reads how long an audio file is.
///
/// Aqua, Cohere, and ElevenLabs report no duration, and both the benchmark's
/// realtime factor and the usage history need one, so the file itself is asked
/// when the provider says nothing.
public enum AudioDuration: Sendable {
    /// Returns the duration of an audio file in seconds, or `nil` when it cannot be read.
    public static func seconds(of file: URL) async -> Double? {
        guard let duration = try? await AVURLAsset(url: file).load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }
}
