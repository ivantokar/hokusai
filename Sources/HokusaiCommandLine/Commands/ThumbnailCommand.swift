import ArgumentParser
import Hokusai

struct ThumbnailCommand: ReportingCommand {
    static let configuration = CommandConfiguration(
        commandName: "thumbnail",
        abstract: "Create a thumbnail with the normal Hokusai resize.",
        discussion: """
            Convenience syntax for an optional EXIF auto-rotation followed by a \
            resize, with the semantics of `hokusai resize` and the library. \
            Sources smaller than the target may be upscaled. The output format \
            is inferred from the output file extension; an existing output file \
            is overwritten.
            """
    )

    @OptionGroup var files: ImageFilesOptions
    @OptionGroup var diagnostics: DiagnosticsOptions

    @Option(help: "Target width in pixels.")
    var width: Int

    @Option(help: "Target height in pixels. Omit to preserve the source aspect ratio. Required for --crop values other than 'none'.")
    var height: Int?

    @Option(help: "Crop strategy ('center' is accepted for 'centre'; none = fit inside, no crop).")
    var crop = CropStrategyArgument.none

    @Flag(help: "Do not apply EXIF auto-rotation (it is applied by default).")
    var noRotate = false

    var plan: ThumbnailPlan {
        ThumbnailPlan(width: width, height: height, crop: crop, autoOrient: !noRotate)
    }

    func validate() throws {
        try plan.validate()
    }

    func execute(reporter: any Reporter) async throws {
        let thumbnail = try plan.apply(to: Hokusai(url: files.inputURL))
        let info = try await thumbnail.write(to: files.outputURL)

        reporter.success("Saved thumbnail")
        reporter.panel("Result", rows: [
            ("Input", reporter.displayPath(files.input)),
            ("Output", reporter.displayPath(files.output)),
            ("Size", "\(info.width)x\(info.height)"),
            ("Crop", crop.rawValue),
        ])
    }
}
