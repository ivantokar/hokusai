import ArgumentParser
import Foundation

struct BenchmarkCompareCommand: ReportingCommand {
    static let configuration = CommandConfiguration(
        commandName: "compare",
        abstract: "Compare two benchmark results (advisory).",
        discussion: """
            Cells are matched by workload, evaluation limit and libvips setting, \
            and compared on median latency and on the worker's peak resident \
            memory. A change is flagged only when it exceeds both the relative \
            and the absolute threshold. Compare runs \
            from the same machine and native stack; differences are listed as \
            warnings. The exit status is always zero.
            """
    )

    @Argument(help: "Result of the base commit.")
    var base: String

    @Argument(help: "Result of the candidate commit.")
    var candidate: String

    @Option(help: "Relative change that counts as meaningful (0.10 = 10%).")
    var relativeThreshold = 0.10

    @Option(help: "Absolute change in milliseconds that counts as meaningful.")
    var absoluteThresholdMs = 5.0

    @Option(help: "Relative growth of peak resident memory that counts as meaningful (0.20 = 20%).")
    var memoryRelativeThreshold = 0.20

    @Option(help: "Absolute growth of peak resident memory in MiB that counts as meaningful.")
    var memoryAbsoluteThresholdMib = 32.0

    @OptionGroup var diagnostics: DiagnosticsOptions

    func validate() throws {
        guard relativeThreshold >= 0, relativeThreshold.isFinite, absoluteThresholdMs >= 0, absoluteThresholdMs.isFinite,
            memoryRelativeThreshold >= 0, memoryRelativeThreshold.isFinite, memoryAbsoluteThresholdMib >= 0, memoryAbsoluteThresholdMib.isFinite
        else {
            throw ValidationError("thresholds must be finite and not negative")
        }
    }

    func execute(reporter: any Reporter) async throws {
        let comparison = ResultComparison(
            base: try load(base), candidate: try load(candidate),
            thresholds: .init(
                relative: relativeThreshold, absoluteMs: absoluteThresholdMs,
                memoryRelative: memoryRelativeThreshold, memoryAbsoluteBytes: memoryAbsoluteThresholdMib * 1_048_576))

        reporter.header("Benchmark comparison")
        for warning in comparison.warnings { reporter.info("Warning: \(warning)") }
        reporter.table(
            headers: ["Workload", "Eval", "libvips", "Base p50", "Cand p50", "Delta", "Req/s", "Verdict", "Peak RSS", "Memory"],
            rows: comparison.rows.map { row in
                [
                    row.workload, "\(row.evaluations)", row.vipsConcurrency,
                    BenchmarkTable.format(row.baseMs), BenchmarkTable.format(row.candidateMs),
                    row.deltaPercent.map { String(format: "%+.1f%%", $0 * 100) } ?? "n/a",
                    String(format: "%.2f → %.2f", row.baseRequestsPerSecond, row.candidateRequestsPerSecond),
                    row.verdict.rawValue,
                    String(format: "%.0f → %.0f MB", Double(row.baseResidentBytes) / 1_048_576, Double(row.candidateResidentBytes) / 1_048_576),
                    row.memoryVerdict.rawValue,
                ]
            })
        if comparison.rows.isEmpty { reporter.info("No cells in common.") }
    }

    private func load(_ path: String) throws -> BenchmarkRun {
        let run = try JSONDecoder().decode(BenchmarkRun.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        guard run.schemaVersion == BenchmarkSchema.version else {
            throw BenchmarkError("\(path) uses result schema \(run.schemaVersion); this build reads \(BenchmarkSchema.version)")
        }
        return run
    }
}
