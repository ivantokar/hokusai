import Foundation

/// One named case of a benchmark run.
struct BenchmarkCaseResult: Encodable {
    let name: String
    let stats: SampleStatistics
    let samplesMs: [Double]

    init(name: String, samplesMs: [Double]) {
        self.name = name
        self.stats = SampleStatistics(samplesMs: samplesMs)
        self.samplesMs = samplesMs
    }
}

/// Everything one benchmark invocation measured. This is the JSON document.
struct BenchmarkReport: Encodable {
    let generatedAt: String
    let warmup: Int
    let iterations: Int
    let cases: [BenchmarkCaseResult]

    /// The table rows shown in the terminal.
    var tableRows: [[String]] {
        cases.map { result in
            [
                result.name,
                Self.formatMs(result.stats.meanMs),
                Self.formatMs(result.stats.medianMs),
                Self.formatMs(result.stats.p95Ms),
                String(format: "%.2f", result.stats.opsPerSecond),
            ]
        }
    }

    static let tableHeaders = ["Case", "Mean", "Median", "P95", "Ops/s"]

    /// Writes the report deterministically to a local JSON file.
    func write(toPath path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: URL(fileURLWithPath: path))
    }

    static func formatMs(_ value: Double) -> String {
        String(format: "%.2f ms", value)
    }
}
