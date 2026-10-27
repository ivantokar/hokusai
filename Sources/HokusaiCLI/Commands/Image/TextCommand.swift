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

    /// Maps command-line options to a `TextStyle`, draws the layer, and saves it.
    ///
    /// Shadow colour applies only when both shadow offsets are supplied, which
    /// avoids constructing an invisible or positionless shadow layer.
    mutating func run() async throws {
        let prompt = PromptService()
        try Hokusai.initialize()

        let image = try Hokusai(url: URL(fileURLWithPath: input))

        var style = TextStyle(fontSize: fontSize, color: try CLIParser.parseColor(color), alignment: CLIParser.parseTextAlign(align))
        let lowered = font.lowercased()
        if font.contains("/") || lowered.hasSuffix(".ttf") || lowered.hasSuffix(".otf") {
            style.fontFile = URL(fileURLWithPath: font)
        } else {
            style.font = font
        }
        if let strokeWidth {
            style.stroke = TextStroke(color: try CLIParser.parseColor(strokeColor ?? "0,0,0,255"), width: strokeWidth)
        }
        if let shadowOffsetX, let shadowOffsetY {
            var shadowStyle = TextShadow(offsetX: Int(shadowOffsetX.rounded()), offsetY: Int(shadowOffsetY.rounded()))
            if let shadowColor { shadowStyle.color = try CLIParser.parseColor(shadowColor) }
            if let shadowOpacity {
                let c = shadowStyle.color
                shadowStyle.color = Color(red: c.red, green: c.green, blue: c.blue, opacity: min(max(shadowOpacity, 0), 1))
            }
            style.shadow = shadowStyle
        }
        style.rotation = rotation ?? 0

        let layout: TextLayout
        switch (textWidth, textHeight) {
        case (let width?, let height?): layout = .fit(width: width, height: height)
        case (let width?, nil): layout = .width(width)
        case (nil, nil): layout = .natural
        case (nil, _?): throw ValidationError("--text-height needs --text-width")
        }

        let withText = try image.drawText(.plain(text), placement: .at(x: x, y: y), layout: layout, style: style)
        _ = try await withText.write(to: URL(fileURLWithPath: output))

        prompt.success("Saved text image")
        prompt.panel("Result", items: [
            ("Input", prompt.path(input)),
            ("Output", prompt.path(output)),
            ("Text", text),
        ])
    }
}
