import Foundation
import ArgumentParser
import Hokusai
import Prompt

struct ConvertCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "convert",
        abstract: "Convert image format."
    )

    @Option(name: .shortAndLong, help: "Input image path.")
    var input: String

    @Option(name: .shortAndLong, help: "Output image path.")
    var output: String

    @Option(help: "Output format (jpeg|png|webp|avif). Optional if output extension is set.")
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

        let selectedFormat = try CLIParser.parseFormat(format, fallbackPath: output)
        let image = try Hokusai(url: URL(fileURLWithPath: input))
        let configured = try CLIParser.configurePipelineOutput(
            image,
            format: selectedFormat,
            quality: quality,
            compression: compression,
            progressive: progressive,
            stripMetadata: stripMetadata,
            lossless: lossless,
            effort: effort
        )
        _ = try await configured.write(to: URL(fileURLWithPath: output))

        prompt.success("Saved converted image")
        prompt.panel("Result", items: [
            ("Input", prompt.path(input)),
            ("Output", prompt.path(output)),
            ("Format", selectedFormat.rawValue),
        ])
    }
}


