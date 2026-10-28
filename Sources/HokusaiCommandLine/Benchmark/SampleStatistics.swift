import Foundation

/// Descriptive statistics over one set of millisecond samples.
///
/// A percentile is reported only when the sample count can support it; a
/// five-sample run has no meaningful p99, so it is `nil` rather than a
/// fabricated number. Field names are part of the result schema.
struct SampleStatistics: Codable, Equatable {
    let count: Int
    let meanMs: Double
    let minMs: Double
    let maxMs: Double
    let stdDevMs: Double
    let p50Ms: Double?
    let p90Ms: Double?
    let p95Ms: Double?
    let p99Ms: Double?

    /// Fewest samples at which each percentile is reported.
    enum MinimumSamples {
        static let p50 = 1
        static let p90 = 10
        static let p95 = 20
        static let p99 = 100
    }

    init(samplesMs: [Double]) {
        let sorted = samplesMs.sorted()
        count = sorted.count
        let mean = sorted.isEmpty ? 0 : sorted.reduce(0, +) / Double(sorted.count)

        func percentile(_ p: Double, minimum: Int) -> Double? {
            guard sorted.count >= minimum, !sorted.isEmpty else { return nil }
            let rank = Int((p * Double(sorted.count - 1)).rounded())
            return sorted[min(max(rank, 0), sorted.count - 1)]
        }

        let variance = sorted.isEmpty ? 0 : sorted.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(sorted.count)

        meanMs = mean
        minMs = sorted.first ?? 0
        maxMs = sorted.last ?? 0
        stdDevMs = sqrt(max(variance, 0))
        p50Ms = percentile(0.50, minimum: MinimumSamples.p50)
        p90Ms = percentile(0.90, minimum: MinimumSamples.p90)
        p95Ms = percentile(0.95, minimum: MinimumSamples.p95)
        p99Ms = percentile(0.99, minimum: MinimumSamples.p99)
    }
}
