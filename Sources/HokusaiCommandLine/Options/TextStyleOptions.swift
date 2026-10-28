import ArgumentParser
import Foundation
import Hokusai

/// Typography flags of `text`, mapped onto the public ``TextStyle`` and ``TextLayout``.
struct TextStyleOptions: ParsableArguments {
    @Option(help: "Font family or Pango font description, e.g. \"sans\" or \"Serif Bold\".")
    var font = "sans"

    @Option(help: "Path to a font file to load instead of an installed family.")
    var fontFile: String?

    @Option(help: "Font size.")
    var fontSize = 48

    @Option(help: "Text colour as r,g,b[,a] (0...255).", transform: ColorParser.parse)
    var color: Color = .white

    @Option(help: "Text alignment.")
    var align = TextAlignmentArgument.left

    @Option(help: "Optional max text width.")
    var textWidth: Int?

    @Option(help: "Optional max text height. Needs --text-width.")
    var textHeight: Int?

    @Option(help: "Stroke width. Enables the stroke.")
    var strokeWidth: Double?

    @Option(help: "Stroke colour as r,g,b[,a] (default 0,0,0,255). Needs --stroke-width.", transform: ColorParser.parse)
    var strokeColor: Color?

    @Option(help: "Shadow offset X. Enables the shadow together with --shadow-offset-y.")
    var shadowOffsetX: Int?

    @Option(help: "Shadow offset Y. Enables the shadow together with --shadow-offset-x.")
    var shadowOffsetY: Int?

    @Option(help: "Shadow colour as r,g,b[,a] (default 0,0,0 at 50% opacity). Needs a shadow.", transform: ColorParser.parse)
    var shadowColor: Color?

    @Option(help: "Shadow opacity 0...1, replacing the colour's own alpha. Needs a shadow.")
    var shadowOpacity: Double?

    @Option(help: "Rotation in degrees.")
    var rotation = 0.0

    /// Rejects combinations that would silently drop an option.
    func validate() throws {
        if textHeight != nil && textWidth == nil {
            throw ValidationError("--text-height needs --text-width")
        }
        if strokeColor != nil && strokeWidth == nil {
            throw ValidationError("--stroke-color needs --stroke-width")
        }
        guard (shadowOffsetX == nil) == (shadowOffsetY == nil) else {
            throw ValidationError("--shadow-offset-x and --shadow-offset-y must be given together")
        }
        if shadowOffsetX == nil && (shadowColor != nil || shadowOpacity != nil) {
            throw ValidationError("--shadow-color and --shadow-opacity need --shadow-offset-x and --shadow-offset-y")
        }
        if let shadowOpacity, !(shadowOpacity.isFinite && (0...1).contains(shadowOpacity)) {
            throw ValidationError("--shadow-opacity must be in 0...1")
        }
    }

    var style: TextStyle {
        var style = TextStyle(font: font, fontSize: fontSize, color: color, alignment: align.alignment)
        style.fontFile = fontFile.map { URL(fileURLWithPath: $0) }
        style.rotation = rotation
        if let strokeWidth {
            style.stroke = TextStroke(color: strokeColor ?? Color(red: 0, green: 0, blue: 0), width: strokeWidth)
        }
        if let shadowOffsetX, let shadowOffsetY {
            var shadow = TextShadow(offsetX: shadowOffsetX, offsetY: shadowOffsetY)
            if let shadowColor { shadow.color = shadowColor }
            if let shadowOpacity {
                shadow.color = Color(red: shadow.color.red, green: shadow.color.green, blue: shadow.color.blue, opacity: shadowOpacity)
            }
            style.shadow = shadow
        }
        return style
    }

    var layout: TextLayout {
        switch (textWidth, textHeight) {
        case (let width?, let height?): .fit(width: width, height: height)
        case (let width?, nil): .width(width)
        case (nil, _): .natural
        }
    }
}
