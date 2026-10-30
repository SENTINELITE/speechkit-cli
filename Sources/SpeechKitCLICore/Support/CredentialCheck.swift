import Foundation
import SpeechKit

/// The outcome of a live probe for one provider.
public enum CheckStatus: String, Sendable, Codable, Equatable {
    /// The provider transcribed the probe clip.
    case ok
    /// The provider rejected the request.
    case failed
    /// The provider was not probed, because it has no key or no local model.
    case skipped
}

/// What ``CredentialCheck`` found for one provider.
public struct CredentialCheckRow: Sendable, Codable, Equatable {
    /// The `--provider` value.
    public let provider: String
    /// Where the credential would come from on this machine.
    public let source: CredentialSource
    /// The `SPEECHKIT_<PROVIDER>_API_KEY` name, or `nil` for keyless providers.
    public let environmentVariable: String?
    /// The credential with everything but its last four characters hidden.
    public let key: String?
    /// The live probe result, or `nil` when `--live` was not passed.
    public let status: CheckStatus?
    /// How long the live probe took, in seconds.
    public let seconds: Double?
    /// The failure or skip reason, flattened to one line and never truncated.
    public let detail: String?

    /// Creates a row.
    public init(
        provider: String,
        source: CredentialSource,
        environmentVariable: String?,
        key: String?,
        status: CheckStatus? = nil,
        seconds: Double? = nil,
        detail: String? = nil
    ) {
        self.provider = provider
        self.source = source
        self.environmentVariable = environmentVariable
        self.key = key
        self.status = status
        self.seconds = seconds
        self.detail = detail
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case source
        case environmentVariable = "envVar"
        case key
        case status
        case seconds
        case detail
    }

    /// Whether the provider needs a key and has none.
    public var isMissingKey: Bool { source == .notFound }
}

/// Checks where every provider's credential comes from, and optionally whether it works.
///
/// The type takes its environment, its keychain, and its live probe as inputs,
/// so the whole command can be exercised in tests without a keychain prompt or
/// a network hop. ``Keys/Check`` is a thin wrapper that supplies the real ones.
public struct CredentialCheck: Sendable {
    /// What a live probe reports back for one provider.
    public struct ProbeResult: Sendable, Equatable {
        /// The outcome.
        public let status: CheckStatus
        /// How long the probe took, in seconds.
        public let seconds: Double
        /// The reason, for anything but `ok`.
        public let detail: String?

        /// Creates a probe result.
        public init(status: CheckStatus, seconds: Double, detail: String? = nil) {
            self.status = status
            self.seconds = seconds
            self.detail = detail
        }
    }

    /// Transcribes the probe clip with one provider and reports the outcome.
    public typealias Probe = @Sendable (CLIProvider, SpeechCredential?) async -> ProbeResult

    /// How many network providers are probed at once.
    ///
    /// The probes are independent HTTPS round trips, so they overlap, but the
    /// cap keeps a nine-provider check from opening nine sockets and nine model
    /// loads at the same instant.
    public static let concurrencyLimit = 4

    /// The longest a `DETAIL` cell is allowed to be in the table.
    static let detailWidth = 60

    private let environment: [String: String]
    private let store: (any KeychainStoring)?

    /// Creates a check.
    ///
    /// - Parameters:
    ///   - environment: The environment consulted for `SPEECHKIT_*_API_KEY`.
    ///   - store: The keychain consulted when the environment has nothing.
    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        store: (any KeychainStoring)? = KeychainStore()
    ) {
        self.environment = environment
        self.store = store
    }

    // MARK: - Provider selection

    /// Resolves the positional provider names into providers.
    ///
    /// An empty list and the word `all` both mean every provider. Names are
    /// case insensitive, and duplicates collapse while keeping enum order.
    ///
    /// - Throws: ``CLIError/usage(_:)`` when a name is not a provider.
    public static func providers(named names: [String]) throws -> [CLIProvider] {
        let cleaned = names.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        if cleaned.isEmpty || cleaned.contains("all") { return CLIProvider.allCases }

        var selected = Swift.Set<CLIProvider>()
        for name in cleaned {
            guard let provider = CLIProvider(argument: name) else {
                throw CLIError.usage(
                    "\(name) is not a provider. Valid values: \(CLIProvider.allValueStrings.joined(separator: ", ")), all."
                )
            }
            selected.insert(provider)
        }
        return CLIProvider.allCases.filter { selected.contains($0) }
    }

    // MARK: - Presence

    /// Returns the credential each provider would use, without contacting anyone.
    public func rows(for providers: [CLIProvider]) -> [CredentialCheckRow] {
        providers.map { provider in
            let found = credential(for: provider)
            return CredentialCheckRow(
                provider: provider.rawValue,
                source: found.source,
                environmentVariable: provider.requiresCredential
                    ? CredentialResolver.environmentVariableName(for: provider)
                    : nil,
                key: found.key?.redactedAPIKey
            )
        }
    }

    // MARK: - Live

    /// Runs the live probe for every provider that has a credential or needs none.
    ///
    /// Providers with no key are reported `skipped` rather than probed, and the
    /// exit code still reflects the missing key. Apple and VOZ transcribe on
    /// device through main-actor isolated runners, so they run one at a time
    /// ahead of the network providers, which overlap up to
    /// ``concurrencyLimit``.
    public func liveRows(
        for providers: [CLIProvider],
        probe: @escaping Probe
    ) async -> [CredentialCheckRow] {
        let base = rows(for: providers)
        var results: [String: ProbeResult] = [:]

        let onDevice = providers.filter { !$0.requiresCredential }
        let networked = providers.filter { $0.requiresCredential && credential(for: $0).credential != nil }

        for provider in onDevice {
            results[provider.rawValue] = await probe(provider, nil)
        }

        await withTaskGroup(of: (String, ProbeResult).self) { group in
            var next = 0
            let running = min(Self.concurrencyLimit, networked.count)
            while next < running {
                let provider = networked[next]
                let credential = self.credential(for: provider).credential
                group.addTask { (provider.rawValue, await probe(provider, credential)) }
                next += 1
            }
            while let finished = await group.next() {
                results[finished.0] = finished.1
                if next < networked.count {
                    let provider = networked[next]
                    let credential = self.credential(for: provider).credential
                    group.addTask { (provider.rawValue, await probe(provider, credential)) }
                    next += 1
                }
            }
        }

        return base.map { row in
            guard let result = results[row.provider] else {
                return CredentialCheckRow(
                    provider: row.provider,
                    source: row.source,
                    environmentVariable: row.environmentVariable,
                    key: row.key,
                    status: .skipped,
                    seconds: nil,
                    detail: "no key"
                )
            }
            return CredentialCheckRow(
                provider: row.provider,
                source: row.source,
                environmentVariable: row.environmentVariable,
                key: row.key,
                status: result.status,
                seconds: result.seconds,
                detail: result.detail.map(Self.singleLine)
            )
        }
    }

    // MARK: - Rendering

    /// Renders rows as a fixed-width table.
    ///
    /// - Parameters:
    ///   - rows: The rows to render.
    ///   - live: Whether to include the `STATUS`, `TIME`, and `DETAIL` columns.
    public static func table(_ rows: [CredentialCheckRow], live: Bool) -> String {
        var headers = ["provider", "source", "env var", "key"]
        if live { headers += ["status", "time", "detail"] }

        let cells = rows.map { row -> [String] in
            var line = [
                row.provider,
                row.source.rawValue,
                row.environmentVariable ?? "-",
                row.key ?? "-"
            ]
            if live {
                line += [
                    row.status?.rawValue ?? "-",
                    row.seconds.map { String(format: "%.1f", $0) } ?? "-",
                    row.detail.map { truncate($0, to: detailWidth) } ?? "-"
                ]
            }
            return line
        }
        return TextTable(headers: headers, rows: cells).render()
    }

    /// Encodes rows as a JSON array.
    ///
    /// - Throws: Any error raised while encoding.
    public static func json(_ rows: [CredentialCheckRow]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(rows), as: UTF8.self) + "\n"
    }

    /// The one-line note about missing keys, or `nil` when every key is present.
    public static func summary(_ rows: [CredentialCheckRow]) -> String? {
        let needKeys = rows.filter { $0.source != .notNeeded }
        let missing = needKeys.filter(\.isMissingKey).map(\.provider)
        guard !missing.isEmpty else { return nil }
        let noun = needKeys.count == 1 ? "provider has" : "providers have"
        return "\(missing.count) of \(needKeys.count) \(noun) no key: \(missing.joined(separator: ", ")). "
            + "Run 'speechkit keys set <provider>'."
    }

    /// The one-line note about failed probes, or `nil` when none failed.
    public static func failureSummary(_ rows: [CredentialCheckRow]) -> String? {
        let failed = rows.filter { $0.status == .failed }.map(\.provider)
        guard !failed.isEmpty else { return nil }
        let verb = failed.count == 1 ? "provider failed" : "providers failed"
        return "\(failed.count) \(verb) the live check: \(failed.joined(separator: ", "))."
    }

    /// The process exit code for a set of rows.
    ///
    /// A missing key is reported as `3` whether or not anything else failed,
    /// so the presence check and the live check agree on what a missing key
    /// means. `2` is reserved for a key that exists but does not work.
    public static func exitCode(_ rows: [CredentialCheckRow]) -> Int32 {
        if rows.contains(where: \.isMissingKey) { return 3 }
        if rows.contains(where: { $0.status == .failed }) { return 2 }
        return 0
    }

    // MARK: - Helpers

    /// Returns a message as one line, with every run of whitespace collapsed.
    ///
    /// Provider errors often carry a pretty-printed JSON body, whose first line
    /// is just an opening brace, so the message is flattened rather than cut at
    /// the first newline. The table truncates the result; `--json` keeps it
    /// whole.
    static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Shortens a cell to `limit` characters, ending in an ellipsis.
    static func truncate(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit - 3)) + "..."
    }

    /// Where a provider's credential comes from, and the credential itself.
    func credential(for provider: CLIProvider) -> (source: CredentialSource, key: String?, credential: SpeechCredential?) {
        guard provider.requiresCredential else { return (.notNeeded, nil, nil) }

        if let found = CredentialResolver.environmentKey(for: provider, in: environment) {
            return (.environment, found.key, .apiKey(found.key))
        }
        if let key = Self.nonEmpty(try? store?.read(for: provider) ?? nil) {
            return (.keychain, key, .apiKey(key))
        }
        return (.notFound, nil, nil)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - The real probe

extension CredentialCheck {
    /// Returns a probe that transcribes `clip` through SpeechKit.
    ///
    /// The runner comes from ``ProviderRegistry/makeRunner(for:context:)``,
    /// which validates the context before returning, so a provider that cannot
    /// run at all is reported without a network call. Model downloads are
    /// refused: a check is meant to be quick, so a VOZ model that is not on
    /// disk is `skipped` with `model not downloaded` rather than fetched.
    ///
    /// - Parameters:
    ///   - clip: The probe clip every provider transcribes.
    ///   - console: The console runners report progress on.
    public static func liveProbe(clip: URL, console: Console = Console(verbosity: .quiet)) -> Probe {
        { provider, credential in
            let started = Date()
            // One row per provider being probed. It closes without a line of
            // its own: the table below is the report, and a piped run has
            // never printed anything here.
            let task = console.task("keys: checking \(provider.rawValue)")
            defer { Task { await task.finish() } }
            let context = RunContext(
                credential: credential,
                allowsModelDownload: false,
                console: console
            )
            do {
                let runner = try await ProviderRegistry.makeRunner(for: provider, context: context)
                _ = try await runner.transcribe(file: clip)
                await runner.finish()
                return ProbeResult(status: .ok, seconds: Date().timeIntervalSince(started))
            } catch let error as CLIError {
                let elapsed = Date().timeIntervalSince(started)
                if case .modelDownloadRefused = error {
                    return ProbeResult(status: .skipped, seconds: elapsed, detail: "model not downloaded")
                }
                return ProbeResult(
                    status: .failed,
                    seconds: elapsed,
                    detail: singleLine(error.localizedDescription)
                )
            } catch {
                return ProbeResult(
                    status: .failed,
                    seconds: Date().timeIntervalSince(started),
                    detail: singleLine(error.localizedDescription)
                )
            }
        }
    }
}
