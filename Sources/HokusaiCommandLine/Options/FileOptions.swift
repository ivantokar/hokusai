import ArgumentParser
import Foundation

/// The input image and output destination shared by every image command.
struct ImageFilesOptions: ParsableArguments {
    @Option(name: .shortAndLong, help: "Input image path.")
    var input: String

    @Option(name: .shortAndLong, help: "Output image path.")
    var output: String

    var inputURL: URL { URL(fileURLWithPath: input) }
    var outputURL: URL { URL(fileURLWithPath: output) }
}

/// The input image of commands that only read.
struct InputFileOptions: ParsableArguments {
    @Option(name: .shortAndLong, help: "Input image path.")
    var input: String

    var inputURL: URL { URL(fileURLWithPath: input) }
}
