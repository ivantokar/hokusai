import ArgumentParser
import Foundation

struct BenchmarkRunCommand: ReportingCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run workloads across a concurrency matrix, one fresh process per cell.",
        discussion: """
            Two independent dimensions are swept: how many evaluations Hokusai \
            runs at once (--evaluations) and how many threads libvips uses \
            inside each (--vips-concurrency). Every cell is a separate worker \
            process with its own frozen runtime configuration, and every \
            concurrent request reads its own copy of the input.

            Workloads: \(WorkloadCatalog.ids.joined(separator: ", ")).
            Profiles: quick (local smoke) and stable (enough samples for tail \
            latency; percentiles the sample count cannot support are omitted).
            """
    )

    @OptionGroup var files: InputFileOptions
    @OptionGroup var diagnostics: DiagnosticsOptions

    @Option(help: "Comma-separated workload ids.", transform: { $0.split(separator: ",").map(String.init) })
    var workloads: [String] = WorkloadCatalog.defaultIDs

    @Option(help: "Measurement profile: quick or stable.")
    var profile = BenchmarkProfile.quick

    @Option(help: "Comma-separated evaluation limits, e.g. 1,2,4,8.", transform: { try $0.split(separator: ",").map { word in
        guard let value = Int(word.trimmingCharacters(in: .whitespaces)), value >= 1 else { throw ValidationError("'\(word)' is not a positive number") }
        return value
    } })
    var evaluations: [Int] = [1, 2, 4]

    @Option(help: "Comma-separated libvips thread counts or 'auto', e.g. 1,2,auto.", transform: ConcurrencyChoice.parseList)
    var vipsConcurrency: [ConcurrencyChoice] = [.automatic]

    @Option(help: "Concurrent requests per batch (default: twice the evaluation limit).")
    var requests: Int?

    @Option(help: "Write the full result as JSON to this path.")
    var jsonOutput: String?

    func validate() throws {
        for id in workloads where WorkloadCatalog.workload(id: id) == nil {
            throw ValidationError("Unknown workload '\(id)'. Available: \(WorkloadCatalog.ids.joined(separator: ", ")).")
        }
        guard !workloads.isEmpty, !evaluations.isEmpty else { throw ValidationError("Give at least one workload and one evaluation limit.") }
        if let requests, requests < 1 { throw ValidationError("--requests must be at least 1") }
    }

    var plan: BenchmarkPlan {
        BenchmarkPlan(
            workloads: workloads, input: files.input, profile: profile,
            evaluations: evaluations, vipsConcurrency: vipsConcurrency, requests: requests)
    }

    func execute(reporter: any Reporter) async throws {
        try await execute(reporter: reporter, launcher: ProcessWorkerLauncher())
    }

    func execute(reporter: any Reporter, launcher: any WorkerLauncher) async throws {
        let plan = plan
        reporter.header("Benchmark (\(profile.rawValue))")
        reporter.info("\(plan.cells.count) cells, one fresh worker process each")

        var orchestrator = BenchmarkOrchestrator(launcher: launcher)
        orchestrator.onCellStart = { settings in
            reporter.info("\(settings.workload): evaluations \(settings.evaluations), libvips \(settings.vipsConcurrency), \(settings.requests) requests")
        }
        let run = try await orchestrator.run(plan, gitCommit: GitProbe.head(), hokusaiVersion: HokusaiVersion.current)

        reporter.header("Results")
        reporter.table(headers: BenchmarkTable.headers, rows: BenchmarkTable.rows(for: run))

        if let jsonOutput {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(run).write(to: URL(fileURLWithPath: jsonOutput))
            reporter.info("Saved JSON benchmark: \(reporter.displayPath(jsonOutput))")
        }
    }
}

enum HokusaiVersion {
    static let current = "2.0.0-dev"
}
