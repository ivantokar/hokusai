import Foundation

/// Descriptive statistics over one set of millisecond samples.
///
/// Field names are the JSON schema of the benchmark output.
struct SampleStatistics: Encodable, Equatable {
    let meanMs: Double
    let medianMs: Double
    let minMs: Double
    let maxMs: Double
    let p90Ms: Double
    let p95Ms: Double
    let stdDevMs: Double
    let opsPerSecond: Double

    /// Computes percentiles and dispersion. Empty input yields zeroes.
    init(samplesMs: [Double]) {
        let sorted = samplesMs.sorted()
        let count = max(1, sorted.count)
        let mean = sorted.reduce(0, +) / Double(count)

        func percentile(_ p: Double) -> Double {
            guard !sorted.isEmpty else { return 0 }
            let rank = Int((p * Double(sorted.count - 1)).rounded())
            return sorted[min(max(rank, 0), sorted.count - 1)]
        }

        let median: Double
        if sorted.isEmpty {
            median = 0
        } else if sorted.count.isMultiple(of: 2) {
            median = (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        } else {
            median = sorted[sorted.count / 2]
        }

        let variance = sorted.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(count)

        self.meanMs = mean
        self.medianMs = median
        self.minMs = sorted.first ?? 0
        self.maxMs = sorted.last ?? 0
        self.p90Ms = percentile(0.90)
        self.p95Ms = percentile(0.95)
        self.stdDevMs = sqrt(max(variance, 0))
        self.opsPerSecond = mean > 0 ? 1000 / mean : 0
    }
}
