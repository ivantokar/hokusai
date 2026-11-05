import ArgumentParser
import Hokusai

struct InspectCommand: ReportingCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Inspect image metadata.",
        discussion: "Reports what the source file says about itself, not the result of any processing."
    )

    @OptionGroup var files: InputFileOptions
    @OptionGroup var diagnostics: DiagnosticsOptions

    @Flag(help: "Print the metadata as one JSON object instead of a table.")
    var json = false

    func execute(reporter: any Reporter) async throws {
        let metadata = try await Hokusai(url: files.inputURL).metadata()
        if json {
            print(try MetadataSummary.json(for: metadata, input: files.input))
            return
        }

        reporter.header("Image Metadata")
        reporter.panel(reporter.displayPath(files.input), rows: MetadataSummary.rows(for: metadata))
    }
}
