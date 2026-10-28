import ArgumentParser
import Foundation

/// Decides the output format from `--format` and the destination filename.
///
/// The library lets an explicit encoder win over the extension. For an
/// operator that is almost always a mistake, so the command line refuses a
/// conflict instead of writing a file whose name lies about its contents.
enum OutputFormatResolver {
    static func resolve(explicit: OutputFormatArgument?, outputPath: String) throws -> OutputFormatArgument {
        let pathExtension = URL(fileURLWithPath: outputPath).pathExtension
        if pathExtension.lowercased() == "svg" {
            throw ValidationError("SVG is an input format and cannot be written.")
        }
        let fromPath = OutputFormatArgument(pathExtensionOf: outputPath)

        switch (explicit, fromPath) {
        case (let format?, let named?) where format != named:
            throw ValidationError("--format \(format.rawValue) conflicts with the output extension '.\(pathExtension)'. Rename the output or drop --format.")
        case (let format?, _):
            return format
        case (nil, let named?):
            return named
        case (nil, nil):
            throw ValidationError("Could not infer the output format. Use --format or an output extension (\(OutputFormatArgument.allValueStrings.joined(separator: ", "))).")
        }
    }
}
