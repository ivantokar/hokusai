import Foundation

/// Times an operation: discarded warm-up runs, then measured runs.
///
/// It measures and nothing else. Display and JSON are the report's job.
enum SampleCollector {
    /// Returns the wall-clock milliseconds of each measured run.
    static func collect(
        warmup: Int,
        iterations: Int,
        operation: () async throws -> Void
    ) async throws -> [Double] {
        for _ in 0..<max(0, warmup) {
            try await operation()
        }
        var samplesMs: [Double] = []
        for _ in 0..<max(1, iterations) {
            let start = DispatchTime.now().uptimeNanoseconds
            try await operation()
            samplesMs.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        return samplesMs
    }
}
