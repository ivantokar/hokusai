import Foundation
import ArgumentParser
import Hokusai
import Prompt

struct BenchmarkPipelineCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pipeline",
        abstract: "Compare a full WebP pipeline with and without Gaussian blur."
    )

    @Option(name: .shortAndLong, help: "Input image path.")
    var input: String

    @Option(help: "Gaussian blur sigma for the blur-to-WebP case.")
    var sigma: Double = 50

    @Option(help: "WebP quality (1...100).")
    var quality: Int = 80

    @Option(help: "WebP encoder effort (0...9).")
    var effort: Int = 4

    @Option(help: "Warmup runs per case.")
    var warmup: Int = 3

    @Option(help: "Measured iterations per case.")
    var iterations: Int = 10

    @Option(help: "Override libvips concurrency (0 = libvips default). Applied at startup; run one process per value to compare settings.")
    var vipsConcurrency: Int = 0

    @Option(help: "Output JSON file path.")
    var jsonOutput: String?

    /// Validates benchmark inputs before any measurements alter runtime concurrency.
    func validate() throws {
        guard sigma.isFinite, sigma > 0 else {
            throw ValidationError("sigma must be a finite value greater than zero")
        }
        guard (1...100).contains(quality) else {
            throw ValidationError("quality must be in 1...100")
        }
        guard (0...9).contains(effort) else {
            throw ValidationError("effort must be in 0...9")
        }
        guard vipsConcurrency >= 0 else {
            throw ValidationError("vips-concurrency must be zero or greater")
        }
    }

    /// Measures equivalent WebP pipelines.
    ///
    /// Runtime configuration freezes at first use, so `--vips-concurrency` is
    /// applied before initialization and holds for the whole process.
    mutating func run() async throws {
        let prompt = PromptService()
        if vipsConcurrency > 0 {
            try Hokusai.configure(.init(vipsConcurrency: .fixed(vipsConcurrency)))
        }
        try Hokusai.initialize()

        let inputURL = URL(fileURLWithPath: input)
        let metadata = try await Hokusai(url: inputURL).metadata()
        let inputDescription = "\(metadata.width)x\(metadata.height) \(metadata.pixel.hasAlpha ? "RGBA" : "RGB") (\(metadata.format?.rawValue ?? "unknown"))"
        prompt.header("WebP Pipeline Benchmark")
        prompt.panel("Environment", items: [
            ("libvips", try Hokusai.capabilities().libvipsVersion),
            ("Concurrency", Hokusai.runtimeStatus.vipsConcurrency.map(String.init) ?? "unknown"),
            ("Input", inputDescription),
            ("WebP", "Q\(quality), effort \(effort)"),
            ("Blur sigma", "\(sigma)"),
        ])

        var results: [BenchmarkSuiteCaseResult] = []
        let cases: [(String, Bool)] = [
            ("load→webp:q\(quality):effort\(effort)", false),
            ("load→blur:\(sigma)→webp:q\(quality):effort\(effort)", true),
        ]

        for (name, appliesBlur) in cases {
            results.append(try await measure(
                name: name,
                appliesBlur: appliesBlur,
                inputURL: inputURL,
                prompt: prompt
            ))
        }

        let rows = results.map { result in
            [
                result.name,
                BenchmarkRunner.formatMs(result.stats.meanMs),
                BenchmarkRunner.formatMs(result.stats.medianMs),
                BenchmarkRunner.formatMs(result.stats.p95Ms),
                String(format: "%.2f", result.stats.opsPerSecond),
            ]
        }
        prompt.header("Results")
        prompt.table(headers: ["Case", "Mean", "Median", "P95", "Ops/s"], rows: rows, style: .rounded)

        if let jsonOutput {
            try BenchmarkRunner.writeJSON(
                BenchmarkSuitePayload(
                    generatedAt: ISO8601DateFormatter().string(from: Date()),
                    warmup: warmup,
                    iterations: iterations,
                    cases: results
                ),
                to: jsonOutput
            )
            prompt.info("Saved JSON benchmark: \(prompt.path(jsonOutput))")
        }
    }

    /// Times one named load-to-WebP pipeline and retains raw samples for JSON output.
    private func measure(
        name: String,
        appliesBlur: Bool,
        inputURL: URL,
        prompt: PromptService
    ) async throws -> BenchmarkSuiteCaseResult {
        let (stats, samples) = try await BenchmarkRunner.runAsync(
            prompt: prompt,
            name: name,
            warmup: warmup,
            iterations: iterations,
            showHeader: false
        ) {
            let source = try Hokusai(url: inputURL)
            let transformed = appliesBlur ? try source.blur(sigma: sigma) : source
            _ = try await transformed.webp(quality: quality, effort: effort).data()
        }
        return BenchmarkSuiteCaseResult(name: name, stats: stats, samplesMs: samples)
    }
}

