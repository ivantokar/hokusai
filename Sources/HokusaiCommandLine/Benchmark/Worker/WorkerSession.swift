import Foundation
import Hokusai

/// What one worker process was asked to do.
struct WorkerSettings: Equatable {
    var workload: String
    var input: String
    var profile: BenchmarkProfile
    var evaluations: Int
    var vipsConcurrency: ConcurrencyChoice
    var requests: Int

    /// The command line that makes a fresh process run exactly these settings.
    var arguments: [String] {
        [
            "benchmark", "worker",
            "--workload", workload,
            "--input", input,
            "--profile", profile.rawValue,
            "--evaluations", "\(evaluations)",
            "--vips-concurrency", vipsConcurrency.description,
            "--requests", "\(requests)",
        ]
    }

    var runtimeConfiguration: RuntimeConfiguration {
        RuntimeConfiguration(
            maxConcurrentEvaluations: .fixed(evaluations),
            maxQueuedEvaluations: nil,
            vipsConcurrency: vipsConcurrency.limit)
    }
}

/// Runs one workload under one frozen runtime configuration and measures it.
///
/// Each concurrent request reads its own copy of the input, so libvips'
/// operation cache cannot turn independent requests into cache hits.
struct WorkerSession {
    let settings: WorkerSettings
    let workload: any Workload

    func run() async throws -> CellMeasurement {
        // Configuration freezes at first use, so it comes before anything else.
        try Hokusai.configure(settings.runtimeConfiguration)

        let inputURL = URL(fileURLWithPath: settings.input)
        let inputData = try Data(contentsOf: inputURL)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("hokusai-bench-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let sources = try (0..<settings.requests).map { index -> URL in
            let url = scratch.appendingPathComponent("source-\(index).\(inputURL.pathExtension)")
            try inputData.write(to: url)
            return url
        }

        let environment = try EnvironmentProbe.current()
        let highWater = EvaluationHighWater()
        let sampler = Task { await highWater.sample() }
        defer { sampler.cancel() }

        for _ in 0..<settings.profile.warmupIterations {
            _ = try await runBatch(sources)
        }

        var latencies: [Double] = []
        var batches: [Double] = []
        var encodedBytes = 0
        for _ in 0..<settings.profile.measuredIterations {
            let start = DispatchTime.now().uptimeNanoseconds
            let batch = try await runBatch(sources)
            batches.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            latencies += batch.map(\.latencyMs)
            encodedBytes = batch.last?.bytes ?? 0
        }
        sampler.cancel()

        let status = Hokusai.runtimeStatus
        let totalSeconds = batches.reduce(0, +) / 1000
        return CellMeasurement(
            schemaVersion: BenchmarkSchema.version,
            workload: workload.id,
            input: BenchmarkInput(name: inputURL.lastPathComponent, sha256: SHA256.hexDigest(of: inputData), bytes: inputData.count),
            environment: environment,
            runtime: BenchmarkRuntime(
                maxConcurrentEvaluations: status.maxConcurrentEvaluations,
                vipsConcurrency: status.vipsConcurrency,
                vipsConcurrencyRequested: settings.vipsConcurrency.description,
                cachePolicy: "libvips default; unique source per concurrent request"),
            profile: settings.profile.rawValue,
            warmupIterations: settings.profile.warmupIterations,
            measuredIterations: settings.profile.measuredIterations,
            requestsPerIteration: settings.requests,
            latencyMs: SampleStatistics(samplesMs: latencies),
            latencySamplesMs: latencies,
            batchMs: batches,
            requestsPerSecond: totalSeconds > 0 ? Double(latencies.count) / totalSeconds : 0,
            encodedBytes: encodedBytes,
            activeEvaluationsHighWater: await highWater.active,
            queuedEvaluationsHighWater: await highWater.queued,
            peakResidentBytes: EnvironmentProbe.peakResidentBytes)
    }

    /// Submits every request at once and times each from submission to completion.
    private func runBatch(_ sources: [URL]) async throws -> [(latencyMs: Double, bytes: Int)] {
        try await withThrowingTaskGroup(of: (Double, Int).self) { group in
            for source in sources {
                let workload = workload
                group.addTask {
                    let start = DispatchTime.now().uptimeNanoseconds
                    let output = try await workload.pipeline(reading: source).data()
                    return (Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000, output.data.count)
                }
            }
            var results: [(latencyMs: Double, bytes: Int)] = []
            for try await (latency, bytes) in group { results.append((latency, bytes)) }
            return results
        }
    }
}

/// Polls the public runtime status for the busiest moment of a run.
actor EvaluationHighWater {
    private(set) var active = 0
    private(set) var queued = 0

    func sample() async {
        while !Task.isCancelled {
            let status = Hokusai.runtimeStatus
            active = max(active, status.activeEvaluations)
            queued = max(queued, status.queuedEvaluations)
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}
