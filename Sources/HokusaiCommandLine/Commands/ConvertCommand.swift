import ArgumentParser
import Hokusai

struct ConvertCommand: ReportingCommand {
    static let configuration = CommandConfiguration(
        commandName: "convert",
        abstract: "Convert image format."
    )

    @OptionGroup var files: ImageFilesOptions
    @OptionGroup var encoding: EncodingOptions
    @OptionGroup var diagnostics: DiagnosticsOptions

    func validate() throws {
        _ = try OutputFormatResolver.resolve(explicit: encoding.format, outputPath: files.output)
    }

    /// Re-encodes with the selected format. Without `--strip-metadata`
    /// Hokusai's default metadata policy applies unchanged.
    func execute(reporter: any Reporter) async throws {
        let format = try OutputFormatResolver.resolve(explicit: encoding.format, outputPath: files.output)
        var pipeline = try Hokusai(url: files.inputURL)
            .encode(using: EncoderFactory.encoder(for: format, settings: encoding.settings))
        if encoding.stripMetadata {
            pipeline = pipeline.metadataPolicy(.removeAll)
        }
        _ = try await pipeline.write(to: files.outputURL)

        reporter.success("Saved converted image")
        reporter.panel("Result", rows: [
            ("Input", reporter.displayPath(files.input)),
            ("Output", reporter.displayPath(files.output)),
            ("Format", format.rawValue),
        ])
    }
}
