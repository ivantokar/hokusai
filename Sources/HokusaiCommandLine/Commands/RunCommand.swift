import ArgumentParser
import Foundation
import Hokusai

/// `hokusai run`: one pipeline, written as the library writes it.
///
/// The input comes first, then steps named after the API methods in the order they apply, then the
/// output: `hokusai run photo.jpg auto-orient resize --width 1200 --fit cover webp --quality 82 -o out.webp`.
/// The image is decoded once and encoded once, however many steps there are.
struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run a pipeline: an input, steps named after the API methods, and an output.",
        discussion: RunHelp.discussion
    )

    @Argument(parsing: .captureForPassthrough, help: ArgumentHelp("The input, the steps and their options, then -o <output>.", valueName: "pipeline"))
    var arguments: [String] = []

    func run() async throws {
        if arguments.isEmpty || arguments.contains(where: { $0 == "--help" || $0 == "-h" }) && !Self.hasStepBeforeHelp(arguments) {
            print(Self.helpMessage())
            throw ExitCode.success
        }
        var verbose = arguments.contains("--verbose") || arguments.contains("-v")
        do {
            let request = try PipelineParser.parse(arguments)
            verbose = request.verbose
            try await Self.execute(request)
        } catch {
            throw ErrorTranslator.translate(error, verbose: verbose)
        }
    }

    /// `hokusai run resize --help` asks for the help of a step; only a bare `--help` is the run help.
    private static func hasStepBeforeHelp(_ words: [String]) -> Bool {
        guard let help = words.firstIndex(where: { $0 == "--help" || $0 == "-h" }) else { return false }
        return words[..<help].contains { PipelineSteps.names.contains($0) }
    }

    static func execute(_ request: PipelineRequest) async throws {
        guard let output = request.output else {
            throw CommandFailure(message: "give an output with -o <path>, or -o - for standard output")
        }
        var image = try request.source.makeImage()
        for step in request.steps { image = try step.apply(to: image) }

        let info: OutputInfo
        if output == "-" {
            guard image.outputFormat != nil else {
                throw CommandFailure(message: "standard output needs an encoder step (png, jpeg, webp, avif, heif, tiff, gif or pdf): there is no file name to take the format from")
            }
            let result = try await image.data()
            try FileHandle.standardOutput.write(contentsOf: result.data)
            info = result.info
        } else {
            info = try await image.write(to: URL(fileURLWithPath: output))
        }

        if request.json {
            let line = try JSONText.render(info, output: output)
            // Standard output carries the image when it is the destination, so the report goes to standard error.
            if output == "-" { FileHandle.standardError.write(Data((line + "\n").utf8)) } else { print(line) }
        } else if output != "-" {
            TerminalReporter().success("Saved \(output)")
            print("  \(info.format.rawValue), \(info.width)x\(info.height), \(info.byteCount) bytes")
        }
    }
}

/// The machine-readable result of a run: the public `OutputInfo`, as one JSON object.
enum JSONText {
    static func render(_ info: OutputInfo, output: String) throws -> String {
        var object: [String: Any] = [
            "output": output, "format": info.format.rawValue, "width": info.width, "height": info.height, "byteCount": info.byteCount,
            "mimeType": info.format.mimeType,
        ]
        if let pdf = info.pdf { object["pdf"] = ["pageCount": pdf.pageCount, "pageWidth": pdf.pageWidth, "pageHeight": pdf.pageHeight] }
        return String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }
}

enum RunHelp {
    static var discussion: String {
        var lines = [
            "A pipeline is an input, steps in the order they apply, and an output. Each step is named after the API method it calls and takes that method's options, with the method's defaults.",
            "",
            "  hokusai run photo.jpg auto-orient resize --width 1200 --height 630 --fit cover blur --sigma 1.5 webp --quality 82 -o social.webp --json",
            "  hokusai run --text \"Hokusai\" --font-size 48 png -o title.png",
            "  cat photo.jpg | hokusai run - resize --width 400 jpeg -o - > small.jpg",
            "",
            "The input is a path, - for standard input, or --text / --markup for generated text, with its options (--page, --access, --fail-on, --max-bytes, --max-pixels, --max-channels, --revalidate).",
            "-o <path> writes a file, and its extension chooses the encoder when no encoder step is given; -o - writes to standard output and needs an encoder step. --json prints the result (OutputInfo) as one JSON object. -v shows the native diagnostic of a failure.",
            "A value that starts with a dash is written with an equals sign, as in --hue=-30.",
            "",
            "`hokusai run photo.jpg resize --help` prints the options of one step.",
            "",
        ]
        for group in PipelineSteps.groups {
            lines.append("\(group.title):")
            for step in group.steps { lines.append("  \(step.name.padding(toLength: 16, withPad: " ", startingAt: 0)) \(step.summary)") }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
