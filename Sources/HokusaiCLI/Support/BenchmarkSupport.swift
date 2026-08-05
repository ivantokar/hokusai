import Foundation
import ArgumentParser
import Hokusai
import Prompt

enum BenchmarkRunner {
    static func runAsync(
        prompt: PromptService,
        name: String,
        warmup: Int,
        iterations: Int,
        showHeader: Bool = true,
        operation: @escaping @Sendable () async throws -> Void
    ) async throws -> (BenchmarkStats, [Double]) {
        if showHeader {
            prompt.header("Benchmark")
        }
        prompt.info("Case: \(name)")
        prompt.item("Warmup: \(warmup)")
        prompt.item("Iterations: \(iterations)")

        if warmup > 0 {
            for _ in 0..<warmup {
                try await operation()
            }
        }

        var samplesMs: [Double] = []
        let measuredRuns = max(1, iterations)
        for _ in 0..<measuredRuns {
            let start = DispatchTime.now().uptimeNanoseconds
            try await operation()
            let end = DispatchTime.now().uptimeNanoseconds
            samplesMs.append(Double(end - start) / 1_000_000.0)
        }
        return (BenchmarkStats(samplesMs: samplesMs), samplesMs)
    }

    static func run(
        prompt: PromptService,
        name: String,
        warmup: Int,
        iterations: Int,
        showHeader: Bool = true,
        operation: () throws -> Void
    ) throws -> (BenchmarkStats, [Double]) {
        if showHeader {
            prompt.header("Benchmark")
        }
        prompt.info("Case: \(name)")
        prompt.item("Warmup: \(warmup)")
        prompt.item("Iterations: \(iterations)")

        if warmup > 0 {
            try prompt.withSpinner("Warmup (\(warmup) runs)") {
                for _ in 0..<warmup {
                    try operation()
                }
            }
        }

        var samplesMs: [Double] = []
        let measuredRuns = max(1, iterations)
        try prompt.withSpinner("Measure (\(measuredRuns) runs)") {
            for _ in 0..<measuredRuns {
                let start = DispatchTime.now().uptimeNanoseconds
                try operation()
                let end = DispatchTime.now().uptimeNanoseconds
                let elapsedMs = Double(end - start) / 1_000_000.0
                samplesMs.append(elapsedMs)
            }
        }

        let stats = BenchmarkStats(samplesMs: samplesMs)
        return (stats, samplesMs)
    }

    static func printStats(prompt: PromptService, name: String, stats: BenchmarkStats) {
        prompt.panel("Results: \(name)", items: [
            ("Mean", formatMs(stats.meanMs)),
            ("Median", formatMs(stats.medianMs)),
            ("Min", formatMs(stats.minMs)),
            ("Max", formatMs(stats.maxMs)),
            ("P90", formatMs(stats.p90Ms)),
            ("P95", formatMs(stats.p95Ms)),
            ("StdDev", formatMs(stats.stdDevMs)),
            ("Ops/s", String(format: "%.2f", stats.opsPerSecond)),
        ])
    }

    static func writeJSON<T: Encodable>(_ value: T, to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: URL(fileURLWithPath: path))
    }

    static func formatMs(_ value: Double) -> String {
        String(format: "%.2f ms", value)
    }
}

struct BenchmarkStats: Encodable {
    let meanMs: Double
    let medianMs: Double
    let minMs: Double
    let maxMs: Double
    let p90Ms: Double
    let p95Ms: Double
    let stdDevMs: Double
    let opsPerSecond: Double

    init(samplesMs: [Double]) {
        let sorted = samplesMs.sorted()
        let count = max(1, sorted.count)
        let sum = sorted.reduce(0, +)
        let mean = sum / Double(count)

        func percentile(_ p: Double) -> Double {
            guard !sorted.isEmpty else { return 0 }
            let rank = Int((p * Double(sorted.count - 1)).rounded())
            return sorted[min(max(rank, 0), sorted.count - 1)]
        }

        let median: Double
        if sorted.isEmpty {
            median = 0
        } else if sorted.count % 2 == 0 {
            let i = sorted.count / 2
            median = (sorted[i - 1] + sorted[i]) / 2.0
        } else {
            median = sorted[sorted.count / 2]
        }

        let variance = sorted.reduce(0.0) { partial, value in
            let delta = value - mean
            return partial + (delta * delta)
        } / Double(count)

        self.meanMs = mean
        self.medianMs = median
        self.minMs = sorted.first ?? 0
        self.maxMs = sorted.last ?? 0
        self.p90Ms = percentile(0.90)
        self.p95Ms = percentile(0.95)
        self.stdDevMs = sqrt(max(variance, 0))
        self.opsPerSecond = mean > 0 ? 1000.0 / mean : 0
    }
}

struct BenchmarkResultPayload: Encodable {
    let generatedAt: String
    let benchmark: String
    let warmup: Int
    let iterations: Int
    let stats: BenchmarkStats
    let samplesMs: [Double]
}

struct BenchmarkSuiteCaseResult: Encodable {
    let name: String
    let stats: BenchmarkStats
    let samplesMs: [Double]
}

struct BenchmarkSuitePayload: Encodable {
    let generatedAt: String
    let warmup: Int
    let iterations: Int
    let cases: [BenchmarkSuiteCaseResult]
}


