import ArgumentParser
import Foundation

/// The process `benchmark run` launches. It prints one JSON result to
/// standard output and nothing else.
struct BenchmarkWorkerCommand: ReportingCommand {
    static let configuration = CommandConfiguration(
        commandName: "worker",
        abstract: "Run one workload under one frozen runtime configuration (used by `benchmark run`).",
        shouldDisplay: false
    )

    @OptionGroup var files: InputFileOptions
    @OptionGroup var diagnostics: DiagnosticsOptions

    @Option(help: "Workload id.")
    var workload: String

    @Option(help: "Measurement profile.")
    var profile = BenchmarkProfile.quick

    @Option(help: "Maximum concurrent evaluations.")
    var evaluations = 1

    @Option(help: "libvips threads: a number or 'auto'.")
    var vipsConcurrency = ConcurrencyChoice.automatic

    @Option(help: "Concurrent requests per batch.")
    var requests = 2

    func validate() throws {
        guard WorkloadCatalog.workload(id: workload) != nil else {
            throw ValidationError("Unknown workload '\(workload)'.")
        }
        guard evaluations >= 1, requests >= 1 else { throw ValidationError("--evaluations and --requests must be at least 1") }
    }

    func execute(reporter: any Reporter) async throws {
        let settings = WorkerSettings(
            workload: workload, input: files.input, profile: profile,
            evaluations: evaluations, vipsConcurrency: vipsConcurrency, requests: requests)
        let measurement = try await WorkerSession(settings: settings, workload: WorkloadCatalog.workload(id: workload)!).run()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(measurement))
    }
}
