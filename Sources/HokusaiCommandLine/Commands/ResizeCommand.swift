import ArgumentParser
import Hokusai

struct ResizeCommand: ReportingCommand {
    static let configuration = CommandConfiguration(
        commandName: "resize",
        abstract: "Resize an image."
    )

    @OptionGroup var files: ImageFilesOptions
    @OptionGroup var diagnostics: DiagnosticsOptions

    @Option(help: "Target width.")
    var width: Int?

    @Option(help: "Target height.")
    var height: Int?

    @Option(help: "Fit mode.")
    var fit = ResizeFitArgument.inside

    @Option(help: "Resampling kernel.")
    var kernel = ResizeKernelArgument.lanczos3

    @Flag(help: "Prevent upscaling.")
    var withoutEnlargement = false

    @Flag(help: "Prevent downscaling.")
    var withoutReduction = false

    func validate() throws {
        guard width != nil || height != nil else {
            throw ValidationError("Specify --width, --height, or both.")
        }
    }

    func execute(reporter: any Reporter) async throws {
        let resized = try Hokusai(url: files.inputURL).resize(
            width: width, height: height,
            fit: fit.fit, kernel: kernel.kernel,
            withoutEnlargement: withoutEnlargement, withoutReduction: withoutReduction)
        let info = try await resized.write(to: files.outputURL)

        reporter.success("Saved resized image")
        reporter.panel("Result", rows: [
            ("Input", reporter.displayPath(files.input)),
            ("Output", reporter.displayPath(files.output)),
            ("Size", "\(info.width)x\(info.height)"),
        ])
    }
}
