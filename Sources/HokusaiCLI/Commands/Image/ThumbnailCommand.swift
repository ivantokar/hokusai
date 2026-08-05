import Foundation
import ArgumentParser
import Hokusai
import Prompt

struct ThumbnailCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "thumbnail",
        abstract: "Create a thumbnail via the libvips optimised load+resize path (vips_thumbnail).",
        discussion: """
            EXIF auto-rotation is applied by default. Sources smaller than the \
            target are upscaled (libvips default). The output format is inferred \
            from the output file extension; an existing output file is overwritten.
            """
    )

    @Option(name: .shortAndLong, help: "Input image path (must exist).")
    var input: String

    @Option(name: .shortAndLong, help: "Output image path. Format inferred from extension; existing file is overwritten.")
    var output: String

    @Option(help: "Target width in pixels (must be > 0).")
    var width: Int

    @Option(help: "Target height in pixels. Omit to preserve the source aspect ratio. Required for --crop values other than 'none'.")
    var height: Int?

    @Option(help: "Crop strategy: none|centre|attention|entropy (default: none = fit inside, no crop).")
    var crop: String = "none"

    @Flag(help: "Disable EXIF auto-rotation (default: rotate upright per EXIF orientation).")
    var noRotate: Bool = false

    func validate() throws {
        try CLIParser.validateDimension(width, name: "width")
        if let height {
            try CLIParser.validateDimension(height, name: "height")
        }
        let position = try CLIParser.parseThumbnailPosition(crop)
        if position != nil && height == nil {
            throw ValidationError("--crop \(crop) requires --height: a crop needs a fully specified target rectangle.")
        }
    }

    mutating func run() async throws {
        let prompt = PromptService()
        try Hokusai.initialize()

        let position = try CLIParser.parseThumbnailPosition(crop)
        let fit: ResizeFit = position == nil ? .inside : .cover
        let source = try Hokusai(url: URL(fileURLWithPath: input))
        let oriented = noRotate ? source : try source.autoOrient()
        let image = try oriented.resize(width: width, height: height, fit: fit, position: position ?? .center)
        let info = try await image.write(to: URL(fileURLWithPath: output))

        prompt.success("Saved thumbnail")
        prompt.panel("Result", items: [
            ("Input", prompt.path(input)),
            ("Output", prompt.path(output)),
            ("Size", "\(info.width)x\(info.height)"),
            ("Crop", crop),
        ])
    }
}

