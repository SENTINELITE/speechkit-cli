import Foundation

/// Runs one job per input file, a bounded number at a time.
///
/// The per-file function never throws, so one failed upload cannot cancel the
/// task group and lose transcripts that already succeeded. Results come back in
/// input order no matter which file finished first.
public struct BatchRunner: Sendable {
    /// The largest value `--jobs` can take.
    public static let maximumJobs = 8

    /// How many files run at once.
    public let jobs: Int

    /// Creates a runner.
    ///
    /// - Parameters:
    ///   - jobs: The requested `--jobs` value. Values above ``maximumJobs`` are
    ///     capped, and a warning is written to the console.
    ///   - console: The console the cap warning goes to.
    public init(jobs: Int, console: Console = Console()) {
        if jobs > Self.maximumJobs {
            console.warning("--jobs is capped at \(Self.maximumJobs).")
        }
        self.jobs = min(max(jobs, 1), Self.maximumJobs)
    }

    /// Runs `body` over every input and returns the outcomes in input order.
    ///
    /// - Parameters:
    ///   - inputs: The files to process.
    ///   - body: The per-file work. It receives the file, its one-based
    ///     position, and the total count, which is what the progress line needs.
    public func run<Outcome: Sendable>(
        inputs: [URL],
        body: @Sendable @escaping (URL, Int, Int) async -> Outcome
    ) async -> [Outcome] {
        guard !inputs.isEmpty else { return [] }
        let total = inputs.count

        let indexed = await withTaskGroup(
            of: (Int, Outcome).self,
            returning: [(Int, Outcome)].self
        ) { group in
            var next = 0
            var results: [(Int, Outcome)] = []
            results.reserveCapacity(total)

            // Prime the group with at most `jobs` tasks, then start one more
            // each time a task finishes, so no more than `jobs` uploads are in
            // flight at once.
            while next < total, next < jobs {
                let index = next
                let input = inputs[index]
                group.addTask { (index, await body(input, index + 1, total)) }
                next += 1
            }

            while let finished = await group.next() {
                results.append(finished)
                if next < total {
                    let index = next
                    let input = inputs[index]
                    group.addTask { (index, await body(input, index + 1, total)) }
                    next += 1
                }
            }
            return results
        }

        return indexed.sorted { $0.0 < $1.0 }.map(\.1)
    }
}
