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

    @Option(help: "Override libvips concurrency (0 = libvips default).")
    var vipsConcurrency: Int = 0

    @Flag(help: "Also sweep concurrency 1,2,4,8,cores for the blur-to-WebP case.")
    var concurrencySweep: Bool = false

    @Option(help: "Output JSON file path.")
    var jsonOutput: String?

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

    mutating func run() async throws {
        let prompt = PromptService()
        try Hokusai.initialize()

        let savedConcurrency = Hokusai.vipsConcurrency
        if vipsConcurrency > 0 {
            Hokusai.vipsConcurrency = vipsConcurrency
        }
        defer { Hokusai.vipsConcurrency = savedConcurrency }

        let inputURL = URL(fileURLWithPath: input)
        let metadata = try Hokusai(url: inputURL).metadata()
        let inputDescription = "\(metadata.width)x\(metadata.height) \(metadata.hasAlpha ? "RGBA" : "RGB") (\(metadata.format?.rawValue ?? "unknown"))"
        prompt.header("WebP Pipeline Benchmark")
        prompt.panel("Environment", items: [
            ("libvips", Hokusai.vipsVersion),
            ("Concurrency", "\(Hokusai.vipsConcurrency)"),
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

        if concurrencySweep {
            let coreCount = ProcessInfo.processInfo.processorCount
            let levels = [1, 2, 4, 8, coreCount].filter { $0 <= coreCount }.reduce(into: [Int]()) {
                if !$0.contains($1) { $0.append($1) }
            }.sorted()

            for level in levels {
                Hokusai.vipsConcurrency = level
                results.append(try await measure(
                    name: "load→blur:\(sigma)→webp:q\(quality):effort\(effort) (conc=\(level))",
                    appliesBlur: true,
                    inputURL: inputURL,
                    prompt: prompt
                ))
            }
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


