import ArgumentParser
import Hokusai

struct CropCommand: ReportingCommand {
    static let configuration = CommandConfiguration(
        commandName: "crop",
        abstract: "Crop image by rectangle."
    )

    @OptionGroup var files: ImageFilesOptions
    @OptionGroup var diagnostics: DiagnosticsOptions

    @Option(help: "Left offset.")
    var left: Int

    @Option(help: "Top offset.")
    var top: Int

    @Option(help: "Crop width.")
    var width: Int

    @Option(help: "Crop height.")
    var height: Int

    func execute(reporter: any Reporter) async throws {
        let cropped = try Hokusai(url: files.inputURL).extract(x: left, y: top, width: width, height: height)
        _ = try await cropped.write(to: files.outputURL)

        reporter.success("Saved cropped image")
        reporter.panel("Result", rows: [
            ("Input", reporter.displayPath(files.input)),
            ("Output", reporter.displayPath(files.output)),
            ("Crop", "(\(left), \(top)) \(width)x\(height)"),
        ])
    }
}
