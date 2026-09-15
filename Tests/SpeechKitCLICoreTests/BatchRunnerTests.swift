import Foundation
import Testing
@testable import SpeechKitCLICore

@Suite("Batch runner")
struct BatchRunnerTests {
    /// Counts how many jobs are in flight so the cap can be asserted.
    private final class ConcurrencyProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var current = 0
        private(set) var peak = 0

        func enter() {
            lock.withLock {
                current += 1
                peak = max(peak, current)
            }
        }

        func leave() {
            lock.withLock { current -= 1 }
        }
    }

    private func inputs(_ count: Int) -> [URL] {
        (0..<count).map { URL(fileURLWithPath: "/tmp/input-\($0).wav") }
    }

    @Test("Outcomes come back in input order however the jobs interleave")
    func preservesOrder() async {
        let files = inputs(5)
        let results = await BatchRunner(jobs: 3).run(inputs: files) { input, index, total in
            // Later files finish first, so anything relying on completion order
            // would come back reversed.
            try? await Task.sleep(for: .milliseconds(20 * (total - index)))
            return input.lastPathComponent
        }
        #expect(results == files.map(\.lastPathComponent))
    }

    @Test("Each job sees its one-based position and the total")
    func positions() async {
        let results = await BatchRunner(jobs: 2).run(inputs: inputs(4)) { _, index, total in
            "\(index)/\(total)"
        }
        #expect(results == ["1/4", "2/4", "3/4", "4/4"])
    }

    @Test("No more than --jobs files run at once")
    func respectsJobLimit() async {
        let probe = ConcurrencyProbe()
        _ = await BatchRunner(jobs: 2).run(inputs: inputs(6)) { _, _, _ in
            probe.enter()
            try? await Task.sleep(for: .milliseconds(20))
            probe.leave()
            return 0
        }
        #expect(probe.peak <= 2)
    }

    @Test("--jobs is capped at eight and floored at one")
    func jobsCap() {
        #expect(BatchRunner(jobs: 32, console: Console(verbosity: .quiet)).jobs == 8)
        #expect(BatchRunner(jobs: 0).jobs == 1)
        #expect(BatchRunner(jobs: 3).jobs == 3)
    }

    @Test("An empty input list runs nothing")
    func emptyInputs() async {
        let results = await BatchRunner(jobs: 4).run(inputs: []) { _, _, _ in 1 }
        #expect(results.isEmpty)
    }

    @Test("One failed file leaves the others written and exits with code two")
    func oneFailureAmongSuccesses() async {
        let files = inputs(3)
        let outcomes = await BatchRunner(jobs: 3).run(inputs: files) { input, _, _ -> Transcribe.FileOutcome in
            if input.lastPathComponent == "input-1.wav" {
                return Transcribe.FileOutcome(
                    input: input,
                    destinations: [],
                    failure: .transcriptionFailed(file: input, reason: "provider said no")
                )
            }
            return Transcribe.FileOutcome(
                input: input,
                destinations: [.file(input.deletingPathExtension().appendingPathExtension("txt"))],
                failure: nil
            )
        }

        #expect(outcomes.map(\.input) == files)
        let failures = outcomes.compactMap(\.failure)
        #expect(failures.count == 1)
        #expect(failures[0].exitCode == 2)
        #expect(outcomes.filter { $0.failure == nil }.count == 2)
        #expect(outcomes[0].destinations == [.file(URL(fileURLWithPath: "/tmp/input-0.txt"))])
    }
}
