import Foundation

/// Helpers every provider runner shares.
///
/// The model lookup, the notes for options a provider cannot use, and the
/// ordering rule for provider-supplied segments were repeated in eight runners.
/// They live here so a fix lands once.
public enum RunnerSupport {
    /// Returns the model a run should use.
    ///
    /// - Parameters:
    ///   - raw: The `--model` value, or `nil` for the provider default.
    ///   - defaultModel: The model used when `--model` is absent.
    ///   - provider: The provider, named in the error.
    ///   - allowed: The models this call accepts, when the provider accepts
    ///     fewer than every case. ElevenLabs is the only one today: its realtime
    ///     model is a valid `ElevenLabsModelID` that the upload endpoint rejects.
    /// - Throws: ``CLIError/invalidModel(provider:model:valid:)`` when the value
    ///   is not one the provider accepts.
    public static func resolveModel<Model: RawRepresentable & CaseIterable>(
        _ raw: String?,
        default defaultModel: Model,
        provider: CLIProvider,
        allowed: [Model]? = nil
    ) throws -> Model where Model.RawValue == String {
        guard let raw else { return defaultModel }
        let valid = (allowed?.map(\.rawValue)) ?? Model.allCases.map(\.rawValue)
        guard let model = Model(rawValue: raw), valid.contains(raw) else {
            throw CLIError.invalidModel(provider: provider, model: raw, valid: valid)
        }
        return model
    }

    /// Returns the notes for options the provider cannot use.
    ///
    /// Only the values that were actually passed produce a note, and the order
    /// is always timeout, prompt, keywords, so the `warnings` array reads the
    /// same whichever provider produced it.
    ///
    /// - Parameters:
    ///   - prompt: The `--prompt` value, when the provider drops it.
    ///   - keywords: The `--keyword` values, when the provider drops them.
    ///   - timeout: The `--timeout` value, when the provider's client has no
    ///     request timeout.
    ///   - provider: The provider, named in each note.
    public static func droppedOptionWarnings(
        prompt: String? = nil,
        keywords: [String] = [],
        timeout: TimeInterval? = nil,
        for provider: CLIProvider
    ) -> [String] {
        var warnings: [String] = []
        if timeout != nil {
            warnings.append("SpeechKit's \(provider.displayName) client takes no request timeout; --timeout was dropped.")
        }
        if prompt != nil {
            warnings.append("\(provider.displayName) has no prompt parameter; --prompt was dropped.")
        }
        if !keywords.isEmpty {
            warnings.append("\(provider.displayName) has no vocabulary parameter; --keyword was dropped.")
        }
        return warnings
    }

    /// Returns provider segments in start order, without the impossible ones.
    ///
    /// Providers occasionally report a segment out of order, or one whose end
    /// precedes its start, which makes a subtitle file that no player accepts.
    /// The sort is stable, so segments sharing a start keep the provider's
    /// order.
    ///
    /// - Parameter segments: The segments as the provider sent them.
    /// - Returns: The usable segments, in start order.
    public static func orderedSegments(
        _ segments: [TranscriptDocument.Segment]
    ) -> [TranscriptDocument.Segment] {
        segments
            .filter { $0.end >= $0.start }
            .enumerated()
            .sorted { left, right in
                if left.element.start == right.element.start { return left.offset < right.offset }
                return left.element.start < right.element.start
            }
            .map(\.element)
    }
}
