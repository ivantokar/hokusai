import Foundation
import ArgumentParser
import Hokusai
import Prompt

struct RotateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rotate",
        abstract: "Rotate image by degrees."
    )

    @Option(name: .shortAndLong, help: "Input image path.")
    var input: String

    @Option(name: .shortAndLong, help: "Output image path.")
    var output: String

    @Option(help: "Angle in degrees.")
    var angle: Double

    @Option(help: "Optional background RGBA (comma-separated), e.g. 255,255,255,255")
    var background: String?

    /// PURPOSE: Rotate image by arbitrary degree angle and save result.
    mutating func run() async throws {
        let prompt = PromptService()
        try Hokusai.initialize()

        let image = try Hokusai(url: URL(fileURLWithPath: input))
        let rgba = try background.map(CLIParser.parseRGBA)
        let bg = rgba.map { Hokusai.rgba(red: $0[0], green: $0[1], blue: $0[2], opacity: $0[3]) } ?? .transparent
        let rotated = try image.rotate(by: angle, background: bg)
        _ = try await rotated.write(to: URL(fileURLWithPath: output))

        prompt.success("Saved rotated image")
        prompt.panel("Result", items: [
            ("Input", prompt.path(input)),
            ("Output", prompt.path(output)),
            ("Angle", "\(angle)°"),
        ])
    }
}


