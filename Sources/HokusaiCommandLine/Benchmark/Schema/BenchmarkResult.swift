import Foundation

/// Version of the machine-readable result format. Bump it when a field is
/// renamed or its meaning changes, so result tooling can evolve deliberately.
enum BenchmarkSchema {
    static let version = 1
}

/// The machine a measurement was taken on.
struct BenchmarkEnvironment: Codable, Equatable {
    var swiftVersion: String
    var operatingSystem: String
    var cpuCount: Int
    var libvipsVersion: String
    var cairoVersion: String
    var outputFormats: [String]
    var textRendering: Bool
}

/// The frozen runtime configuration one worker process ran with.
struct BenchmarkRuntime: Codable, Equatable {
    var maxConcurrentEvaluations: Int
    /// What libvips actually used.
    var vipsConcurrency: Int?
    /// What was asked for: a number, or `auto`.
    var vipsConcurrencyRequested: String
    /// libvips operation cache policy. Hokusai exposes no cache control, so
    /// this is always the libvips default and workloads use unique sources.
    var cachePolicy: String
}

/// Which input a workload read.
struct BenchmarkInput: Codable, Equatable {
    var name: String
    var sha256: String
    var bytes: Int
}

/// The result of one worker process: one workload under one runtime configuration.
struct CellMeasurement: Codable, Equatable {
    var schemaVersion: Int
    var workload: String
    var input: BenchmarkInput
    var environment: BenchmarkEnvironment
    var runtime: BenchmarkRuntime
    var profile: String
    var warmupIterations: Int
    var measuredIterations: Int
    var requestsPerIteration: Int
    /// End-to-end latency of every measured request, queueing included.
    var latencyMs: SampleStatistics
    var latencySamplesMs: [Double]
    /// Wall-clock time of each measured batch of concurrent requests.
    var batchMs: [Double]
    var requestsPerSecond: Double
    var encodedBytes: Int
    var activeEvaluationsHighWater: Int
    var queuedEvaluationsHighWater: Int
    /// Peak resident set size of the worker process.
    var peakResidentBytes: Int
}

/// A complete benchmark invocation: every cell, with provenance.
struct BenchmarkRun: Codable, Equatable {
    var schemaVersion: Int
    var generatedAt: String
    var gitCommit: String
    var hokusaiVersion: String
    var profile: String
    var cells: [CellMeasurement]
}
