import Foundation

/// Compares two benchmark runs cell by cell.
///
/// It reports deltas and flags a change only when both the relative and the
/// absolute difference are meaningful, so one noisy sample or a tiny workload
/// does not raise an alarm. Peak resident memory is judged the same way, with
/// its own thresholds. Results are advisory.
struct ResultComparison {
    struct Thresholds: Equatable {
        var relative = 0.10
        var absoluteMs = 5.0
        /// Growth of a worker's peak resident set that counts as meaningful.
        var memoryRelative = 0.20
        var memoryAbsoluteBytes = 32.0 * 1_048_576
    }

    enum Verdict: String { case regression, improvement, unchanged, notComparable }

    struct Row: Equatable {
        let workload: String
        let evaluations: Int
        let vipsConcurrency: String
        let baseMs: Double?
        let candidateMs: Double?
        let baseRequestsPerSecond: Double
        let candidateRequestsPerSecond: Double
        let verdict: Verdict
        let baseResidentBytes: Int
        let candidateResidentBytes: Int
        /// Judged on peak resident memory; a larger candidate is a `regression`.
        let memoryVerdict: Verdict

        var deltaMs: Double? {
            guard let baseMs, let candidateMs else { return nil }
            return candidateMs - baseMs
        }

        var deltaPercent: Double? {
            guard let baseMs, let candidateMs, baseMs > 0 else { return nil }
            return (candidateMs - baseMs) / baseMs
        }
    }

    let rows: [Row]
    /// Why the two runs may not be comparable (different machine or native stack).
    let warnings: [String]

    init(base: BenchmarkRun, candidate: BenchmarkRun, thresholds: Thresholds = Thresholds()) {
        var warnings: [String] = []
        if base.profile != candidate.profile {
            warnings.append("profiles differ: \(base.profile) vs \(candidate.profile)")
        }
        if let a = base.cells.first?.environment, let b = candidate.cells.first?.environment {
            if a.libvipsVersion != b.libvipsVersion { warnings.append("libvips differs: \(a.libvipsVersion) vs \(b.libvipsVersion)") }
            if a.cpuCount != b.cpuCount { warnings.append("CPU count differs: \(a.cpuCount) vs \(b.cpuCount)") }
            if a.operatingSystem != b.operatingSystem { warnings.append("operating system differs") }
        }
        if let a = base.cells.first?.input, let b = candidate.cells.first?.input, a.sha256 != b.sha256 {
            warnings.append("inputs differ (\(a.name) vs \(b.name))")
        }

        func key(_ cell: CellMeasurement) -> String {
            "\(cell.workload)|\(cell.runtime.maxConcurrentEvaluations)|\(cell.runtime.vipsConcurrencyRequested)"
        }
        let baseByKey = Dictionary(base.cells.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })

        rows = candidate.cells.compactMap { cell in
            guard let before = baseByKey[key(cell)] else { return nil }
            let baseMs = before.latencyMs.p50Ms
            let candidateMs = cell.latencyMs.p50Ms
            return Row(
                workload: cell.workload,
                evaluations: cell.runtime.maxConcurrentEvaluations,
                vipsConcurrency: cell.runtime.vipsConcurrencyRequested,
                baseMs: baseMs, candidateMs: candidateMs,
                baseRequestsPerSecond: before.requestsPerSecond,
                candidateRequestsPerSecond: cell.requestsPerSecond,
                verdict: Self.verdict(baseMs: baseMs, candidateMs: candidateMs, thresholds: thresholds),
                baseResidentBytes: before.peakResidentBytes,
                candidateResidentBytes: cell.peakResidentBytes,
                memoryVerdict: Self.verdict(
                    base: Double(before.peakResidentBytes), candidate: Double(cell.peakResidentBytes),
                    relative: thresholds.memoryRelative, absolute: thresholds.memoryAbsoluteBytes))
        }
        self.warnings = warnings
    }

    static func verdict(baseMs: Double?, candidateMs: Double?, thresholds: Thresholds) -> Verdict {
        verdict(base: baseMs, candidate: candidateMs, relative: thresholds.relative, absolute: thresholds.absoluteMs)
    }

    /// A change counts only when it exceeds both the relative and the absolute bound.
    static func verdict(base: Double?, candidate: Double?, relative: Double, absolute: Double) -> Verdict {
        guard let base, let candidate, base > 0 else { return .notComparable }
        let delta = candidate - base
        guard abs(delta) >= absolute, abs(delta) / base >= relative else { return .unchanged }
        return delta > 0 ? .regression : .improvement
    }
}
