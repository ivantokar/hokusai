import ArgumentParser
import Foundation
import Hokusai

struct PipelineBenchmarkCommand: ReportingCommand {
    static let configuration = CommandConfiguration(
        commandName: "pipeline",
        abstract: "Compare a full WebP pipeline with and without Gaussian blur.",
        discussion: """
            One process uses one frozen runtime configuration. To compare \
            libvips concurrency values, run one process per value.
            """
    )

    @OptionGroup var files: InputFileOptions
    @OptionGroup var diagnostics: DiagnosticsOptions

    @Option(help: "Gaussian blur sigma for the blur-to-WebP case.")
    var sigma = 50.0

    @Option(help: "WebP quality.")
    var quality = 80

    @Option(help: "WebP encoder effort.")
    var effort = 4

    @Option(help: "Warmup runs per case.")
    var warmup = 3

    @Option(help: "Measured iterations per case.")
    var iterations = 10

    @Option(help: "Override libvips concurrency for this process (0 = libvips default).")
    var vipsConcurrency = 0

    @Option(help: "Output JSON file path.")
    var jsonOutput: String?

    func validate() throws {
        guard vipsConcurrency >= 0 else {
            throw ValidationError("--vips-concurrency must be zero or greater")
        }
        guard warmup >= 0, iterations >= 1 else {
            throw ValidationError("--warmup must be zero or greater and --iterations at least 1")
        }
    }

    /// Runtime configuration freezes at first use, so the concurrency setting
    /// is applied before anything else touches Hokusai.
    func execute(reporter: any Reporter) async throws {
        if vipsConcurrency > 0 {
            try Hokusai.configure(.init(vipsConcurrency: .fixed(vipsConcurrency)))
        }

        let metadata = try await Hokusai(url: files.inputURL).metadata()
        let inputDescription = "\(metadata.width)x\(metadata.height) \(metadata.pixel.hasAlpha ? "RGBA" : "RGB") (\(metadata.format?.rawValue ?? "unknown"))"
        reporter.header("WebP Pipeline Benchmark")
        reporter.panel("Environment", rows: [
            ("libvips", try Hokusai.capabilities().libvipsVersion),
            ("Concurrency", Hokusai.runtimeStatus.vipsConcurrency.map(String.init) ?? "unknown"),
            ("Input", inputDescription),
            ("WebP", "Q\(quality), effort \(effort)"),
            ("Blur sigma", "\(sigma)"),
            ("Runs", "\(warmup) warmup, \(iterations) measured"),
        ])

        let cases: [(name: String, blur: Bool)] = [
            ("load→webp:q\(quality):effort\(effort)", false),
            ("load→blur:\(sigma)→webp:q\(quality):effort\(effort)", true),
        ]
        var results: [BenchmarkCaseResult] = []
        for benchmarkCase in cases {
            reporter.info("Case: \(benchmarkCase.name)")
            let samples = try await SampleCollector.collect(warmup: warmup, iterations: iterations) {
                _ = try await pipeline(blurred: benchmarkCase.blur).data()
            }
            results.append(BenchmarkCaseResult(name: benchmarkCase.name, samplesMs: samples))
        }

        let report = BenchmarkReport(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            warmup: warmup, iterations: iterations, cases: results)
        reporter.header("Results")
        reporter.table(headers: BenchmarkReport.tableHeaders, rows: report.tableRows)

        if let jsonOutput {
            try report.write(toPath: jsonOutput)
            reporter.info("Saved JSON benchmark: \(reporter.displayPath(jsonOutput))")
        }
    }

    /// The measured pipeline, built from the public API like any other.
    private func pipeline(blurred: Bool) throws -> Hokusai {
        let source = try Hokusai(url: files.inputURL)
        return try (blurred ? source.blur(sigma: sigma) : source).webp(quality: quality, effort: effort)
    }
}
