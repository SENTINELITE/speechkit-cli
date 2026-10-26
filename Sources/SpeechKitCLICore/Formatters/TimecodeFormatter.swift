import Foundation

/// Formats cue times for SubRip and WebVTT.
///
/// SubRip separates the milliseconds with a comma and WebVTT with a full stop.
/// Both use at least two digits for the hour and allow the hour to run past 99
/// for very long recordings. Times are rounded to the nearest millisecond,
/// never go negative, and a cue never ends before it starts.
public enum TimecodeFormatter {
    /// The millisecond separator of a subtitle format.
    public enum Style: Sendable {
        /// `hh:mm:ss,mmm`, as SubRip writes it.
        case srt
        /// `hh:mm:ss.mmm`, as WebVTT writes it.
        case vtt

        /// The character between the seconds and the milliseconds.
        var separator: String {
            switch self {
            case .srt: return ","
            case .vtt: return "."
            }
        }
    }

    /// Returns a time in seconds rounded to whole milliseconds, clamped at zero.
    public static func milliseconds(_ seconds: Double) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int((seconds * 1000).rounded())
    }

    /// Returns a timecode for a time in seconds.
    ///
    /// - Parameters:
    ///   - seconds: The time, in seconds. Negative and non-finite values become zero.
    ///   - style: Which separator to use.
    public static func timecode(_ seconds: Double, style: Style) -> String {
        timecode(milliseconds: milliseconds(seconds), style: style)
    }

    /// Returns a timecode for a whole number of milliseconds.
    public static func timecode(milliseconds total: Int, style: Style) -> String {
        let total = max(total, 0)
        let hours = total / 3_600_000
        let minutes = (total % 3_600_000) / 60_000
        let seconds = (total % 60_000) / 1000
        let millis = total % 1000
        return String(format: "%02d:%02d:%02d%@%03d", hours, minutes, seconds, style.separator, millis)
    }

    /// Returns the cue time line, such as `00:00:01,520 --> 00:00:04,640`.
    ///
    /// A cue that would end at or before it starts is stretched by one
    /// millisecond, which keeps zero-length words playable in both formats.
    ///
    /// - Parameters:
    ///   - start: The cue start, in seconds.
    ///   - end: The cue end, in seconds.
    ///   - style: Which separator to use.
    public static func range(start: Double, end: Double, style: Style) -> String {
        let startMilliseconds = milliseconds(start)
        var endMilliseconds = milliseconds(end)
        if endMilliseconds <= startMilliseconds {
            endMilliseconds = startMilliseconds + 1
        }
        return "\(timecode(milliseconds: startMilliseconds, style: style)) --> \(timecode(milliseconds: endMilliseconds, style: style))"
    }

    /// Returns a compact reading timestamp, such as `6:45.8` or `1:02:03.4`.
    ///
    /// Plain text uses this rather than a subtitle timecode. The time is
    /// truncated to tenths rather than rounded, so a line never claims to start
    /// after its first word.
    ///
    /// - Parameter seconds: The time, in seconds. Negative and non-finite values become zero.
    public static func clock(_ seconds: Double) -> String {
        let tenths = seconds.isFinite && seconds > 0 ? Int(seconds * 10 + 1e-6) : 0
        let hours = tenths / 36_000
        let minutes = (tenths % 36_000) / 600
        let wholeSeconds = (tenths % 600) / 10
        let fraction = tenths % 10
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%d", hours, minutes, wholeSeconds, fraction)
        }
        return String(format: "%d:%02d.%d", minutes, wholeSeconds, fraction)
    }
}
