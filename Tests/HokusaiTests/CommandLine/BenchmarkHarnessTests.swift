import ArgumentParser
import Foundation
import Testing
@testable import HokusaiCommandLine

/// The benchmark harness: planning, orchestration, statistics and comparison.
/// Workers are not spawned here; the CLI smoke test runs the real binary.
@Suite struct BenchmarkHarnessTests {
    // MARK: - Statistics

    @Test func percentilesAreOmittedWhenTheSampleCountCannotSupportThem() {
        let few = SampleStatistics(samplesMs: [5, 1, 3, 2, 4])
        #expect(few.p50Ms == 3)
        #expect(few.p90Ms == nil && few.p95Ms == nil && few.p99Ms == nil)

        let some = SampleStatistics(samplesMs: (1...20).map(Double.init))
        #expect(some.p90Ms != nil && some.p95Ms != nil && some.p99Ms == nil)

        let many = SampleStatistics(samplesMs: (1...100).map(Double.init))
        #expect(many.p99Ms == 99 || many.p99Ms == 100)
        #expect(many.count == 100 && many.minMs == 1 && many.maxMs == 100 && many.meanMs == 50.5)
    }

    @Test func noSamplesProduceNoPercentilesAndNoTrap() {
        let none = SampleStatistics(samplesMs: [])
        #expect(none.count == 0 && none.p50Ms == nil && none.meanMs == 0)
    }

    @Test func sha256MatchesKnownVectors() {
        #expect(SHA256.hexDigest(of: Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(SHA256.hexDigest(of: Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let long = Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)
        #expect(SHA256.hexDigest(of: long) == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }

    // MARK: - Plan

    @Test func theMatrixCoversEveryWorkloadAndBothConcurrencyDimensions() {
        let plan = BenchmarkPlan(
            workloads: ["thumbnail-jpeg", "blur-webp"], input: "in.jpg", profile: .quick,
            evaluations: [1, 4], vipsConcurrency: [.fixed(2), .automatic], requests: nil)
        let cells = plan.cells

        #expect(cells.count == 8)
        #expect(Set(cells.map { "\($0.workload)/\($0.evaluations)/\($0.vipsConcurrency)" }).count == 8)
        // The default request count exceeds the evaluation limit, so the queue is exercised.
        #expect(cells.filter { $0.evaluations == 4 }.allSatisfy { $0.requests == 8 })
        #expect(cells.filter { $0.evaluations == 1 }.allSatisfy { $0.requests == 2 })
    }

    @Test func aWorkerCommandLineParsesBackIntoTheSameSettings() throws {
        let settings = WorkerSettings(
            workload: "cover-webp", input: "a b.jpg", profile: .stable,
            evaluations: 3, vipsConcurrency: .fixed(2), requests: 7)
        #expect(Array(settings.arguments.prefix(2)) == ["benchmark", "worker"])

        let worker = try BenchmarkWorkerCommand.parse(Array(settings.arguments.dropFirst(2)))
        #expect(worker.workload == "cover-webp" && worker.files.input == "a b.jpg")
        #expect(worker.profile == .stable && worker.evaluations == 3 && worker.requests == 7)
        #expect(worker.vipsConcurrency == .fixed(2))

        let auto = WorkerSettings(workload: "blur-webp", input: "x", profile: .quick, evaluations: 1, vipsConcurrency: .automatic, requests: 2)
        #expect(try BenchmarkWorkerCommand.parse(Array(auto.arguments.dropFirst(2))).vipsConcurrency == .automatic)
    }

    @Test func settingsFreezeAsRuntimeConfiguration() {
        let settings = WorkerSettings(workload: "x", input: "x", profile: .quick, evaluations: 4, vipsConcurrency: .fixed(2), requests: 8)
        #expect(settings.runtimeConfiguration.maxConcurrentEvaluations.fixedValue == 4)
        #expect(settings.runtimeConfiguration.vipsConcurrency.fixedValue == 2)
        #expect(settings.runtimeConfiguration.maxQueuedEvaluations == nil)
    }

    @Test func concurrencyListsAcceptNumbersAndAutoOnly() throws {
        #expect(try ConcurrencyChoice.parseList("1, 2,auto") == [.fixed(1), .fixed(2), .automatic])
        for bad in ["0", "-1", "x", "", "1,,2"] {
            #expect(throws: (any Error).self, "\(bad)") { try ConcurrencyChoice.parseList(bad) }
        }
    }

    @Test func commandsRejectUnknownWorkloadsAndBadCounts() {
        for arguments in [
            ["--input", "in.jpg", "--workloads", "nope"],
            ["--input", "in.jpg", "--evaluations", "0"],
            ["--input", "in.jpg", "--requests", "0"],
            ["--input", "in.jpg", "--vips-concurrency", "fast"],
            ["--input", "in.jpg", "--profile", "extreme"],
        ] {
            #expect(throws: (any Error).self, "\(arguments)") { try BenchmarkRunCommand.parse(arguments) }
        }
        #expect(throws: (any Error).self) { try BenchmarkWorkerCommand.parse(["--input", "in.jpg", "--workload", "nope"]) }
    }

    @Test func everyCatalogWorkloadHasAUniqueIDAndTheDefaultsExist() {
        #expect(Set(WorkloadCatalog.ids).count == WorkloadCatalog.ids.count)
        #expect(WorkloadCatalog.defaultIDs.allSatisfy { WorkloadCatalog.workload(id: $0) != nil })
    }

    // MARK: - Orchestration

    private final class FakeLauncher: WorkerLauncher, @unchecked Sendable {
        private(set) var launched: [[String]] = []
        var response: (WorkerSettings) throws -> Data

        init(response: @escaping (WorkerSettings) throws -> Data) { self.response = response }

        func launch(arguments: [String]) async throws -> Data {
            launched.append(arguments)
            let worker = try BenchmarkWorkerCommand.parse(Array(arguments.dropFirst(2)))
            return try response(WorkerSettings(
                workload: worker.workload, input: worker.files.input, profile: worker.profile,
                evaluations: worker.evaluations, vipsConcurrency: worker.vipsConcurrency, requests: worker.requests))
        }
    }

    static func cell(_ settings: WorkerSettings, p50: Double = 10, requestsPerSecond: Double = 100, libvips: String = "8.16.1") -> CellMeasurement {
        let samples = Array(repeating: p50, count: 10)
        return CellMeasurement(
            schemaVersion: BenchmarkSchema.version, workload: settings.workload,
            input: BenchmarkInput(name: "in.jpg", sha256: "abc", bytes: 1),
            environment: BenchmarkEnvironment(
                swiftVersion: "6.0", operatingSystem: "os", cpuCount: 8, libvipsVersion: libvips,
                cairoVersion: "1.18.0", outputFormats: ["png"], textRendering: true),
            runtime: BenchmarkRuntime(
                maxConcurrentEvaluations: settings.evaluations, vipsConcurrency: 1,
                vipsConcurrencyRequested: settings.vipsConcurrency.description, cachePolicy: "default"),
            profile: settings.profile.rawValue, warmupIterations: 1, measuredIterations: 5,
            requestsPerIteration: settings.requests,
            latencyMs: SampleStatistics(samplesMs: samples), latencySamplesMs: samples, batchMs: [1],
            requestsPerSecond: requestsPerSecond, encodedBytes: 1,
            activeEvaluationsHighWater: 1, queuedEvaluationsHighWater: 0, peakResidentBytes: 1)
    }

    @Test func eachCellGetsItsOwnFreshWorkerAndTheResultsAreCollectedInOrder() async throws {
        let launcher = FakeLauncher { try JSONEncoder().encode(Self.cell($0)) }
        let plan = BenchmarkPlan(
            workloads: ["thumbnail-jpeg"], input: "in.jpg", profile: .quick,
            evaluations: [1, 2], vipsConcurrency: [.fixed(1), .automatic], requests: nil)

        let run = try await BenchmarkOrchestrator(launcher: launcher).run(plan, gitCommit: "abc123", hokusaiVersion: "x")

        #expect(launcher.launched.count == 4)
        #expect(Set(launcher.launched).count == 4, "every worker has distinct settings")
        #expect(run.cells.map { "\($0.runtime.maxConcurrentEvaluations)/\($0.runtime.vipsConcurrencyRequested)" } == ["1/1", "1/auto", "2/1", "2/auto"])
        #expect(run.gitCommit == "abc123" && run.schemaVersion == BenchmarkSchema.version)
    }

    @Test func aFailingWorkerFailsTheRunInsteadOfBeingSkipped() async {
        let launcher = FakeLauncher { _ in throw WorkerFailure(arguments: ["benchmark", "worker"], status: 1, standardError: "boom") }
        let plan = BenchmarkPlan(workloads: ["blur-webp"], input: "in.jpg", profile: .quick, evaluations: [1], vipsConcurrency: [.automatic], requests: nil)
        await #expect(throws: WorkerFailure.self) {
            try await BenchmarkOrchestrator(launcher: launcher).run(plan, gitCommit: "", hokusaiVersion: "")
        }
    }

    @Test func workerOutputThatIsNotAResultOrHasAnotherSchemaIsRejected() throws {
        #expect(throws: BenchmarkError.self) { try BenchmarkOrchestrator.decode(Data("not json".utf8)) }

        let settings = WorkerSettings(workload: "blur-webp", input: "x", profile: .quick, evaluations: 1, vipsConcurrency: .automatic, requests: 2)
        var future = Self.cell(settings)
        future.schemaVersion = BenchmarkSchema.version + 1
        let data = try JSONEncoder().encode(future)
        #expect(throws: BenchmarkError.self) { try BenchmarkOrchestrator.decode(data) }
    }

    @Test func resultsRoundTripThroughJSON() throws {
        let settings = WorkerSettings(workload: "blur-webp", input: "x", profile: .stable, evaluations: 2, vipsConcurrency: .fixed(2), requests: 4)
        let original = Self.cell(settings)
        #expect(try BenchmarkOrchestrator.decode(JSONEncoder().encode(original)) == original)
    }

    // MARK: - Comparison

    private func run(p50: Double, libvips: String = "8.16.1") -> BenchmarkRun {
        let settings = WorkerSettings(workload: "blur-webp", input: "x", profile: .quick, evaluations: 2, vipsConcurrency: .automatic, requests: 4)
        return BenchmarkRun(
            schemaVersion: 1, generatedAt: "", gitCommit: "", hokusaiVersion: "", profile: "quick",
            cells: [Self.cell(settings, p50: p50, libvips: libvips)])
    }

    @Test func aChangeNeedsBothARelativeAndAnAbsoluteDeltaToBeFlagged() {
        let thresholds = ResultComparison.Thresholds(relative: 0.10, absoluteMs: 5)
        // 50% slower but only 2 ms: noise on a tiny workload.
        #expect(ResultComparison.verdict(baseMs: 4, candidateMs: 6, thresholds: thresholds) == .unchanged)
        // 20 ms slower but only 2%: noise on a large workload.
        #expect(ResultComparison.verdict(baseMs: 1000, candidateMs: 1020, thresholds: thresholds) == .unchanged)
        #expect(ResultComparison.verdict(baseMs: 100, candidateMs: 130, thresholds: thresholds) == .regression)
        #expect(ResultComparison.verdict(baseMs: 100, candidateMs: 70, thresholds: thresholds) == .improvement)
        #expect(ResultComparison.verdict(baseMs: nil, candidateMs: 70, thresholds: thresholds) == .notComparable)
    }

    @Test func comparisonMatchesCellsAndWarnsAboutDifferentNativeStacks() {
        let same = ResultComparison(base: run(p50: 100), candidate: run(p50: 150))
        #expect(same.rows.count == 1 && same.rows[0].verdict == .regression)
        #expect(same.rows[0].deltaPercent == 0.5 && same.warnings.isEmpty)

        let different = ResultComparison(base: run(p50: 100), candidate: run(p50: 100, libvips: "8.18.7"))
        #expect(different.warnings.contains { $0.contains("libvips") })
    }
}
