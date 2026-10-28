import ArgumentParser
import Hokusai

struct TextCommand: ReportingCommand {
    static let configuration = CommandConfiguration(
        commandName: "text",
        abstract: "Draw text on image."
    )

    @OptionGroup var files: ImageFilesOptions
    @OptionGroup var typography: TextStyleOptions
    @OptionGroup var diagnostics: DiagnosticsOptions

    @Option(help: "Text to draw.")
    var text: String

    @Option(help: "X position.")
    var x = 0

    @Option(help: "Y position.")
    var y = 0

    func execute(reporter: any Reporter) async throws {
        let drawn = try Hokusai(url: files.inputURL).drawText(
            .plain(text), placement: .at(x: x, y: y),
            layout: typography.layout, style: typography.style)
        _ = try await drawn.write(to: files.outputURL)

        reporter.success("Saved text image")
        reporter.panel("Result", rows: [
            ("Input", reporter.displayPath(files.input)),
            ("Output", reporter.displayPath(files.output)),
            ("Text", text),
        ])
    }
}
