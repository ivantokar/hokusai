import Foundation
import ArgumentParser
import Hokusai
import Prompt

/// PURPOSE: CLI entrypoint exposing operational and benchmark commands.
/// CONSTRAINTS:
/// - Commands must initialize/shutdown Hokusai runtime per invocation.
/// - Keep output human-readable for local operator workflows.
/// AI HINTS:
/// - Prefer additive subcommands over behavior changes in existing commands.
@main
struct HokusaiCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hokusai",
        abstract: "First-party CLI for testing Hokusai image operations and benchmarks.",
        subcommands: [
            InfoCommand.self,
            InspectCommand.self,
            ResizeCommand.self,
            ConvertCommand.self,
            RotateCommand.self,
            CropCommand.self,
            TextCommand.self,
            BenchmarkCommand.self,
        ]
    )
}

struct InfoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Show Hokusai and libvips version information."
    )

    /// PURPOSE: Print runtime versions for Hokusai and libvips.
    mutating func run() async throws {
        let prompt = PromptService()
        try Hokusai.initialize()
        defer { Hokusai.shutdown() }

        prompt.header("Hokusai CLI")
        prompt.panel("Runtime", items: [
            ("Hokusai", Hokusai.version),
            ("libvips", Hokusai.vipsVersion),
        ])
        prompt.summary("Ready")
    }
}

struct InspectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Inspect image metadata."
    )

    @Option(name: .shortAndLong, help: "Input image path.")
    var input: String

    /// PURPOSE: Show decoded metadata for a local image file.
    mutating func run() async throws {
        let prompt = PromptService()
        try Hokusai.initialize()
        defer { Hokusai.shutdown() }

        let image = try Hokusai.loadFromFile(input)
        let metadata = try image.metadata()

        prompt.header("Image Metadata")
        prompt.panel(prompt.path(input), items: [
            ("Width", "\(metadata.width) px"),
            ("Height", "\(metadata.height) px"),
            ("Channels", "\(metadata.channels)"),
            ("Has Alpha", metadata.hasAlpha ? "yes" : "no"),
            ("Format", metadata.format?.rawValue ?? "unknown"),
        ])
    }
}

struct ResizeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resize",
        abstract: "Resize an image."
    )

    @Option(name: .shortAndLong, help: "Input image path.")
    var input: String

    @Option(name: .shortAndLong, help: "Output image path.")
    var output: String

    @Option(help: "Target width.")
    var width: Int?

    @Option(help: "Target height.")
    var height: Int?

    @Option(help: "Fit mode: inside|outside|fill|cover|contain")
    var fit: String = "inside"

    @Option(help: "Kernel: nearest|linear|cubic|mitchell|lanczos2|lanczos3")
    var kernel: String = "lanczos3"

    @Flag(help: "Prevent upscaling.")
    var withoutEnlargement = false

    @Flag(help: "Prevent downscaling.")
    var withoutReduction = false

    /// PURPOSE: Resize an input image and save to destination path.
    mutating func run() async throws {
        let prompt = PromptService()
        try Hokusai.initialize()
        defer { Hokusai.shutdown() }

        let image = try Hokusai.loadFromFile(input)

        var options = ResizeOptions()
        options.fit = CLIParser.parseFit(fit)
        options.kernel = CLIParser.parseKernel(kernel)
        options.withoutEnlargement = withoutEnlargement
        options.withoutReduction = withoutReduction

        let resized = try image.resize(width: width, height: height, options: options)
        try resized.toFile(output)

        prompt.success("Saved resized image")
        prompt.panel("Result", items: [
            ("Input", prompt.path(input)),
            ("Output", prompt.path(output)),
            ("Size", "\(try resized.width)x\(try resized.height)"),
        ])
    }
}

struct ConvertCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "convert",
        abstract: "Convert image format."
    )

    @Option(name: .shortAndLong, help: "Input image path.")
    var input: String

    @Option(name: .shortAndLong, help: "Output image path.")
    var output: String

    @Option(help: "Output format (jpeg|png|webp|gif|tiff|avif|heif). Optional if output extension is set.")
    var format: String?

    @Option(help: "Quality for lossy formats.")
    var quality: Int?

    @Option(help: "Compression (PNG/TIFF).")
    var compression: Int?

    @Flag(help: "Use progressive/interlaced output when supported.")
    var progressive = false

    @Flag(help: "Strip metadata where supported.")
    var stripMetadata = false

    @Flag(help: "Use lossless mode where supported.")
    var lossless = false

    @Option(help: "Encoder effort where supported.")
    var effort: Int?

    /// PURPOSE: Re-encode image with explicit format and encoder options.
    mutating func run() async throws {
        let prompt = PromptService()
        try Hokusai.initialize()
        defer { Hokusai.shutdown() }

        let image = try Hokusai.loadFromFile(input)

        var options = SaveOptions()
        options.format = try CLIParser.parseFormat(format, fallbackPath: output)
        options.quality = quality
        options.compression = compression
        options.progressive = progressive
        options.stripMetadata = stripMetadata
        options.lossless = lossless
        options.effort = effort

        try image.toFile(output, options: options)

        prompt.success("Saved converted image")
        prompt.panel("Result", items: [
            ("Input", prompt.path(input)),
            ("Output", prompt.path(output)),
            ("Format", options.format?.rawValue ?? "auto"),
        ])
    }
}

struct RotateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rotate",
        abstract: "Rotate image by degrees."
    )

    @Option(name: .shortAndLong, help: "Input image path.")
    var input: String

    @Option(name: .shortAndLong, help: "Output image path.")
    var output: String

    @Option(help: "Angle in degrees.")
    var angle: Double

    @Option(help: "Optional background RGBA (comma-separated), e.g. 255,255,255,255")
    var background: String?

    /// PURPOSE: Rotate image by arbitrary degree angle and save result.
    mutating func run() async throws {
        let prompt = PromptService()
        try Hokusai.initialize()
        defer { Hokusai.shutdown() }

        let image = try Hokusai.loadFromFile(input)
        let bg = try background.map(CLIParser.parseRGBA)
        let rotated = try image.rotate(angle: .custom(angle), background: bg)
        try rotated.toFile(output)

        prompt.success("Saved rotated image")
        prompt.panel("Result", items: [
            ("Input", prompt.path(input)),
            ("Output", prompt.path(output)),
            ("Angle", "\(angle)°"),
        ])
    }
}

struct CropCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "crop",
        abstract: "Crop image by rectangle."
    )

    @Option(name: .shortAndLong, help: "Input image path.")
    var input: String

    @Option(name: .shortAndLong, help: "Output image path.")
    var output: String

    @Option(help: "Left offset.")
    var left: Int

    @Option(help: "Top offset.")
    var top: Int

    @Option(help: "Crop width.")
    var width: Int

    @Option(help: "Crop height.")
    var height: Int

    mutating func run() async throws {
        let prompt = PromptService()
        try Hokusai.initialize()
        defer { Hokusai.shutdown() }

        let image = try Hokusai.loadFromFile(input)
        let cropped = try image.crop(left: left, top: top, width: width, height: height)
        try cropped.toFile(output)

        prompt.success("Saved cropped image")
        prompt.panel("Result", items: [
            ("Input", prompt.path(input)),
            ("Output", prompt.path(output)),
            ("Crop", "(\(left), \(top)) \(width)x\(height)"),
        ])
    }
}

struct TextCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "text",
        abstract: "Draw text on image."
    )

    @Option(name: .shortAndLong, help: "Input image path.")
    var input: String

    @Option(name: .shortAndLong, help: "Output image path.")
    var output: String

    @Option(help: "Text to draw.")
    var text: String

    @Option(help: "X position.")
    var x: Int = 0

    @Option(help: "Y position.")
    var y: Int = 0

    @Option(help: "Font family name or font file path.")
    var font: String = "sans"

    @Option(help: "Font size.")
    var fontSize: Int = 48

    @Option(help: "Text RGBA as comma-separated values.")
    var color: String = "255,255,255,255"

    @Option(help: "Alignment: left|center|right")
    var align: String = "left"

    @Option(help: "Optional max text width.")
    var textWidth: Int?

    @Option(help: "Optional max text height.")
    var textHeight: Int?

    @Option(help: "Optional stroke width.")
    var strokeWidth: Double?

    @Option(help: "Stroke RGBA as comma-separated values.")
    var strokeColor: String?

    @Option(help: "Optional shadow offset X.")
    var shadowOffsetX: Double?

    @Option(help: "Optional shadow offset Y.")
    var shadowOffsetY: Double?

    @Option(help: "Shadow RGBA as comma-separated values.")
    var shadowColor: String?

    @Option(help: "Shadow opacity 0..1.")
    var shadowOpacity: Double?

    @Option(help: "Rotation in degrees.")
    var rotation: Double?

    mutating func run() async throws {
        let prompt = PromptService()
        try Hokusai.initialize()
        defer { Hokusai.shutdown() }

        let image = try Hokusai.loadFromFile(input)

        var options = TextOptions()
        options.font = font
        options.fontSize = fontSize
        options.color = try CLIParser.parseRGBA(color)
        options.align = CLIParser.parseTextAlign(align)
        options.width = textWidth
        options.height = textHeight
        options.strokeWidth = strokeWidth
        if let strokeColor { options.strokeColor = try CLIParser.parseRGBA(strokeColor) }

        if let shadowOffsetX, let shadowOffsetY {
            options.shadowOffset = (x: shadowOffsetX, y: shadowOffsetY)
            if let shadowColor {
                options.shadowColor = try CLIParser.parseRGBA(shadowColor)
            }
        }

        options.shadowOpacity = shadowOpacity
        options.rotation = rotation

        let withText = try image.drawText(text, x: x, y: y, options: options)
        try withText.toFile(output)

        prompt.success("Saved text image")
        prompt.panel("Result", items: [
            ("Input", prompt.path(input)),
            ("Output", prompt.path(output)),
            ("Text", text),
        ])
    }
}

struct BenchmarkCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "benchmark",
        abstract: "Measure operation performance.",
        subcommands: [BenchmarkOperationCommand.self, BenchmarkSuiteCommand.self]
    )
}

struct BenchmarkOperationCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "op",
        abstract: "Benchmark a single operation."
    )

    @Option(name: .shortAndLong, help: "Input image path.")
    var input: String

    @Option(help: "Operation: resize|convert|rotate|crop|text")
    var operation: String

    @Option(help: "Warmup runs.")
    var warmup: Int = 3

    @Option(help: "Measured iterations.")
    var iterations: Int = 20

    @Option(help: "Output JSON file path.")
    var jsonOutput: String?

    // PURPOSE: Common op knobs
    @Option(help: "Width (resize/crop).")
    var width: Int = 800

    @Option(help: "Height (resize/crop).")
    var height: Int = 600

    @Option(help: "Format (convert).")
    var format: String = "webp"

    @Option(help: "Quality (convert).")
    var quality: Int = 80

    @Option(help: "Angle in degrees (rotate).")
    var angle: Double = 33.0

    @Option(help: "Text (text op).")
    var text: String = "Benchmark"

    mutating func run() async throws {
        let prompt = PromptService()
        let normalizedOp = operation.lowercased()

        try Hokusai.initialize()
        defer { Hokusai.shutdown() }

        let benchmarkName = "op:\(normalizedOp)"
        let (stats, samplesMs) = try BenchmarkRunner.run(
            prompt: prompt,
            name: benchmarkName,
            warmup: warmup,
            iterations: iterations
        ) {
            try runOperation(named: normalizedOp)
        }

        BenchmarkRunner.printStats(prompt: prompt, name: benchmarkName, stats: stats)

        if let jsonOutput {
            let payload = BenchmarkResultPayload(
                generatedAt: ISO8601DateFormatter().string(from: Date()),
                benchmark: benchmarkName,
                warmup: warmup,
                iterations: iterations,
                stats: stats,
                samplesMs: samplesMs
            )
            try BenchmarkRunner.writeJSON(payload, to: jsonOutput)
            prompt.info("Saved JSON benchmark: \(prompt.path(jsonOutput))")
        }
    }

    private func runOperation(named name: String) throws {
        let image = try Hokusai.loadFromFile(input)

        switch name {
        case "resize":
            _ = try image.resize(width: width, height: height).toBuffer(
                options: SaveOptions(format: .jpeg, quality: 85)
            )
        case "convert":
            let fmt = try CLIParser.parseFormat(format, fallbackPath: nil)
            _ = try image.toBuffer(
                options: SaveOptions(format: fmt, quality: quality, compression: 6)
            )
        case "rotate":
            _ = try image.rotate(angle: .custom(angle)).toBuffer(
                options: SaveOptions(format: .jpeg, quality: 85)
            )
        case "crop":
            _ = try image.crop(left: 0, top: 0, width: width, height: height).toBuffer(
                options: SaveOptions(format: .jpeg, quality: 85)
            )
        case "text":
            var options = TextOptions()
            options.fontSize = 56
            options.color = [255, 255, 255, 255]
            options.strokeColor = [0, 0, 0, 255]
            options.strokeWidth = 2.0
            let rendered = try image.drawText(text, x: 80, y: 140, options: options)
            _ = try rendered.toBuffer(options: SaveOptions(format: .png, compression: 6))
        default:
            throw ValidationError("Unsupported benchmark operation: \(name)")
        }
    }
}

struct BenchmarkSuiteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "suite",
        abstract: "Benchmark a predefined operation suite."
    )

    @Option(name: .shortAndLong, help: "Input image path.")
    var input: String

    @Option(help: "Warmup runs per case.")
    var warmup: Int = 3

    @Option(help: "Measured iterations per case.")
    var iterations: Int = 20

    @Option(help: "Output JSON file path.")
    var jsonOutput: String?

    mutating func run() async throws {
        let prompt = PromptService()
        try Hokusai.initialize()
        defer { Hokusai.shutdown() }
        let inputPath = input

        let suiteCases: [(String, () throws -> Void)] = [
            ("resize:1200x800", {
                let image = try Hokusai.loadFromFile(inputPath)
                _ = try image.resize(width: 1200, height: 800).toBuffer(options: SaveOptions(format: .jpeg, quality: 85))
            }),
            ("convert:webp:q80", {
                let image = try Hokusai.loadFromFile(inputPath)
                _ = try image.toBuffer(options: SaveOptions(format: .webp, quality: 80))
            }),
            ("rotate:33", {
                let image = try Hokusai.loadFromFile(inputPath)
                _ = try image.rotate(angle: .custom(33)).toBuffer(options: SaveOptions(format: .jpeg, quality: 85))
            }),
            ("text:stroke-shadow", {
                let image = try Hokusai.loadFromFile(inputPath)
                var options = TextOptions()
                options.fontSize = 64
                options.color = [255, 255, 255, 255]
                options.strokeColor = [0, 0, 0, 255]
                options.strokeWidth = 3.0
                options.shadowOffset = (x: 4, y: 4)
                options.shadowColor = [0, 0, 0, 180]
                let rendered = try image.drawText("Hokusai", x: 80, y: 180, options: options)
                _ = try rendered.toBuffer(options: SaveOptions(format: .png, compression: 6))
            }),
        ]

        var suiteRows: [[String]] = []
        var jsonCases: [BenchmarkSuiteCaseResult] = []

        for (name, operation) in suiteCases {
            let (stats, samples) = try BenchmarkRunner.run(
                prompt: prompt,
                name: name,
                warmup: warmup,
                iterations: iterations,
                showHeader: false
            ) {
                try operation()
            }

            suiteRows.append([
                name,
                BenchmarkRunner.formatMs(stats.meanMs),
                BenchmarkRunner.formatMs(stats.p95Ms),
                String(format: "%.2f", stats.opsPerSecond),
            ])

            jsonCases.append(BenchmarkSuiteCaseResult(name: name, stats: stats, samplesMs: samples))
        }

        prompt.header("Benchmark Suite")
        prompt.table(
            headers: ["Case", "Mean", "P95", "Ops/s"],
            rows: suiteRows,
            style: .rounded
        )

        if let jsonOutput {
            let payload = BenchmarkSuitePayload(
                generatedAt: ISO8601DateFormatter().string(from: Date()),
                warmup: warmup,
                iterations: iterations,
                cases: jsonCases
            )
            try BenchmarkRunner.writeJSON(payload, to: jsonOutput)
            prompt.info("Saved JSON benchmark suite: \(prompt.path(jsonOutput))")
        }
    }
}

enum BenchmarkRunner {
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

enum CLIParser {
    static func parseFit(_ value: String) -> ResizeFit {
        switch value.lowercased() {
        case "inside": return .inside
        case "outside": return .outside
        case "fill": return .fill
        case "cover": return .cover
        case "contain": return .contain
        default: return .inside
        }
    }

    static func parseKernel(_ value: String) -> Kernel {
        switch value.lowercased() {
        case "nearest": return .nearest
        case "linear": return .linear
        case "cubic": return .cubic
        case "mitchell": return .mitchell
        case "lanczos2": return .lanczos2
        default: return .lanczos3
        }
    }

    static func parseTextAlign(_ value: String) -> TextAlignment {
        switch value.lowercased() {
        case "center": return .center
        case "right": return .right
        default: return .left
        }
    }

    static func parseFormat(_ value: String?, fallbackPath: String?) throws -> ImageFormat {
        if let value, !value.isEmpty {
            if let format = parseFormatAlias(value) {
                return format
            }
            throw ValidationError("Unsupported format: \(value)")
        }

        if let fallbackPath,
           let ext = fallbackPath.split(separator: ".").last,
           let format = parseFormatAlias(String(ext)) {
            return format
        }

        throw ValidationError("Could not infer image format. Use --format or output extension.")
    }

    private static func parseFormatAlias(_ value: String) -> ImageFormat? {
        let normalized = value.lowercased()
        if normalized == "jpg" { return .jpeg }
        if normalized == "tif" { return .tiff }
        if normalized == "heic" { return .heif }
        return ImageFormat(rawValue: normalized)
    }

    static func parseRGBA(_ value: String) throws -> [Double] {
        let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 3 || parts.count == 4 else {
            throw ValidationError("RGBA must have 3 or 4 comma-separated numbers")
        }

        var numbers: [Double] = []
        for part in parts {
            guard let number = Double(part) else {
                throw ValidationError("Invalid color component: \(part)")
            }
            numbers.append(min(max(number, 0), 255))
        }

        if numbers.count == 3 {
            numbers.append(255)
        }

        return numbers
    }
}
