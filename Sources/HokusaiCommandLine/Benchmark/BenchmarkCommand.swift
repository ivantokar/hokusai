import ArgumentParser

/// Groups the benchmark subcommands: `run` orchestrates, `worker` is the
/// process `run` launches, and `compare` reads two results.
struct BenchmarkCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "benchmark",
        abstract: "Measure performance in process-isolated workers.",
        subcommands: [BenchmarkRunCommand.self, BenchmarkWorkerCommand.self, BenchmarkCompareCommand.self]
    )
}
