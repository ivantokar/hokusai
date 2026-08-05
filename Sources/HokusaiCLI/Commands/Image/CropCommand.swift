import Foundation
import ArgumentParser
import Hokusai
import Prompt

struct CropCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "crop",
        abstract: "Crop image by rectangle."
    )

    @Option(name: .shortAndLong, help: "Input image path.")
    var input: String

    @Option(name: .shortAndLong, help: "Output image path.")
    var output: String

    @Option(help: "Left offset.")
    var left: Int

    @Option(help: "Top offset.")
    var top: Int

    @Option(help: "Crop width.")
    var width: Int

    @Option(help: "Crop height.")
    var height: Int

    mutating func run() async throws {
        let prompt = PromptService()
        try Hokusai.initialize()

        let cropped = try Hokusai(url: URL(fileURLWithPath: input))
            .extract(x: left, y: top, width: width, height: height)
        _ = try await cropped.write(to: URL(fileURLWithPath: output))

        prompt.success("Saved cropped image")
        prompt.panel("Result", items: [
            ("Input", prompt.path(input)),
            ("Output", prompt.path(output)),
            ("Crop", "(\(left), \(top)) \(width)x\(height)"),
        ])
    }
}


