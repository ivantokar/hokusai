import ArgumentParser
import Hokusai

struct RotateCommand: ReportingCommand {
    static let configuration = CommandConfiguration(
        commandName: "rotate",
        abstract: "Rotate image by degrees."
    )

    @OptionGroup var files: ImageFilesOptions
    @OptionGroup var diagnostics: DiagnosticsOptions

    @Option(help: "Angle in degrees, clockwise.")
    var angle: Double

    @Option(help: "Background for the corners the rotation exposes, as r,g,b[,a] (0...255). Default: transparent.", transform: ColorParser.parse)
    var background: Color = .transparent

    func execute(reporter: any Reporter) async throws {
        let rotated = try Hokusai(url: files.inputURL).rotate(by: angle, background: background)
        _ = try await rotated.write(to: files.outputURL)

        reporter.success("Saved rotated image")
        reporter.panel("Result", rows: [
            ("Input", reporter.displayPath(files.input)),
            ("Output", reporter.displayPath(files.output)),
            ("Angle", "\(angle)°"),
        ])
    }
}
