import Foundation
import ArgumentParser
import Hokusai
import Prompt

struct TextCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "text",
        abstract: "Draw text on image."
    )

    @Option(name: .shortAndLong, help: "Input image path.")
    var input: String

    @Option(name: .shortAndLong, help: "Output image path.")
    var output: String

    @Option(help: "Text to draw.")
    var text: String

    @Option(help: "X position.")
    var x: Int = 0

    @Option(help: "Y position.")
    var y: Int = 0

    @Option(help: "Font family name or font file path.")
    var font: String = "sans"

    @Option(help: "Font size.")
    var fontSize: Int = 48

    @Option(help: "Text RGBA as comma-separated values.")
    var color: String = "255,255,255,255"

    @Option(help: "Alignment: left|center|right")
    var align: String = "left"

    @Option(help: "Optional max text width.")
    var textWidth: Int?

    @Option(help: "Optional max text height.")
    var textHeight: Int?

    @Option(help: "Optional stroke width.")
    var strokeWidth: Double?

    @Option(help: "Stroke RGBA as comma-separated values.")
    var strokeColor: String?

    @Option(help: "Optional shadow offset X.")
    var shadowOffsetX: Double?

    @Option(help: "Optional shadow offset Y.")
    var shadowOffsetY: Double?

    @Option(help: "Shadow RGBA as comma-separated values.")
    var shadowColor: String?

    @Option(help: "Shadow opacity 0..1.")
    var shadowOpacity: Double?

    @Option(help: "Rotation in degrees.")
    var rotation: Double?

    mutating func run() async throws {
        let prompt = PromptService()
        try Hokusai.initialize()

        let image = try Hokusai(url: URL(fileURLWithPath: input))

        var options = TextOptions()
        options.font = font
        options.fontSize = fontSize
        options.color = try CLIParser.parseRGBA(color)
        options.align = CLIParser.parseTextAlign(align)
        options.width = textWidth
        options.height = textHeight
        options.strokeWidth = strokeWidth
        if let strokeColor { options.strokeColor = try CLIParser.parseRGBA(strokeColor) }

        if let shadowOffsetX, let shadowOffsetY {
            options.shadowOffset = (x: shadowOffsetX, y: shadowOffsetY)
            if let shadowColor {
                options.shadowColor = try CLIParser.parseRGBA(shadowColor)
            }
        }

        options.shadowOpacity = shadowOpacity
        options.rotation = rotation

        let withText = try image.drawText(text, x: x, y: y, options: options)
        _ = try await withText.write(to: URL(fileURLWithPath: output))

        prompt.success("Saved text image")
        prompt.panel("Result", items: [
            ("Input", prompt.path(input)),
            ("Output", prompt.path(output)),
            ("Text", text),
        ])
    }
}


