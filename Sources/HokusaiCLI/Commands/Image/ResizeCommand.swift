import Foundation
import ArgumentParser
import Hokusai
import Prompt

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

    func validate() throws {
        if let width {
            try CLIParser.validateDimension(width, name: "width")
        }
        if let height {
            try CLIParser.validateDimension(height, name: "height")
        }
    }

    /// PURPOSE: Resize an input image and save to destination path.
    mutating func run() async throws {
        let prompt = PromptService()
        try Hokusai.initialize()

        let resized = try Hokusai(url: URL(fileURLWithPath: input)).resize(
            width: width,
            height: height,
            fit: CLIParser.parseFit(fit),
            kernel: CLIParser.parsePipelineKernel(kernel),
            withoutEnlargement: withoutEnlargement,
            withoutReduction: withoutReduction
        )
        let info = try await resized.write(to: URL(fileURLWithPath: output))

        prompt.success("Saved resized image")
        prompt.panel("Result", items: [
            ("Input", prompt.path(input)),
            ("Output", prompt.path(output)),
            ("Size", "\(info.width)x\(info.height)"),
        ])
    }
}


