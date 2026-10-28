import Foundation

/// How a run is laid out in the terminal.
enum BenchmarkTable {
    static let headers = ["Workload", "Eval", "libvips", "Req/s", "p50", "p95", "p99", "Active", "Peak RSS"]

    static func rows(for run: BenchmarkRun) -> [[String]] {
        run.cells.map { cell in
            [
                cell.workload,
                "\(cell.runtime.maxConcurrentEvaluations)",
                cell.runtime.vipsConcurrencyRequested,
                String(format: "%.2f", cell.requestsPerSecond),
                format(cell.latencyMs.p50Ms),
                format(cell.latencyMs.p95Ms),
                format(cell.latencyMs.p99Ms),
                "\(cell.activeEvaluationsHighWater)",
                String(format: "%.0f MB", Double(cell.peakResidentBytes) / 1_048_576),
            ]
        }
    }

    /// `n/a` marks a percentile the sample count cannot support.
    static func format(_ milliseconds: Double?) -> String {
        milliseconds.map { String(format: "%.1f ms", $0) } ?? "n/a"
    }
}
