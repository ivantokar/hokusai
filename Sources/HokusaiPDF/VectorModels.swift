import Foundation
import Hokusai

// Typed values for vector PDF pages. Coordinates are in PDF points (1/72 inch) with the origin at the
// top-left corner of the page and y growing downwards, so a layout reads the way it is written.

/// A point on a page, in points from the top-left corner.
public struct VectorPoint: Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A rectangle on a page, in points. `x` and `y` are its top-left corner.
public struct VectorRect: Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    func validate(_ name: String) throws {
        guard [x, y, width, height].allSatisfy(\.isFinite), width > 0, height > 0 else {
            throw HokusaiError.invalidOption(name: name, reason: "must have finite coordinates and a width and height greater than zero")
        }
    }
}

/// The size of a page.
public enum VectorPageSize: Sendable, Hashable {
    /// ISO A4, 210 × 297 mm.
    case a4(PDFPageOrientation = .portrait)
    /// US Letter, 8.5 × 11 in.
    case letter(PDFPageOrientation = .portrait)
    /// A custom size in points; each side in `1...14400` (200 inches, the PDF limit).
    case points(width: Double, height: Double)

    /// The size in points.
    var dimensions: (width: Double, height: Double) {
        switch self {
        case .a4(let orientation): orientation == .portrait ? (595.276, 841.890) : (841.890, 595.276)
        case .letter(let orientation): orientation == .portrait ? (612, 792) : (792, 612)
        case .points(let width, let height): (width, height)
        }
    }

    func validate() throws {
        let size = dimensions
        for (name, side) in [("page width", size.width), ("page height", size.height)] where !side.isFinite || !(1...14400).contains(side) {
            throw HokusaiError.invalidOption(name: name, reason: "must be a finite value from 1 to 14400 points")
        }
    }
}

/// One colour at a position along a gradient.
public struct GradientStop: Sendable, Hashable {
    /// Where the colour sits along the gradient, `0...1`.
    public var offset: Double
    public var color: Color

    public init(offset: Double, color: Color) {
        self.offset = offset
        self.color = color
    }
}

/// How an area is filled: one colour or a linear gradient.
public enum VectorPaint: Sendable, Hashable {
    case color(Color)
    /// A linear gradient across the filled area. `angle` is in degrees, clockwise from the
    /// direction left to right: 0 runs left to right, 90 top to bottom. The gradient line is
    /// as long as the area needs, so the first stop is at one corner and the last at the opposite one.
    case linearGradient(stops: [GradientStop], angle: Double)

    /// A two-colour gradient.
    public static func linearGradient(from start: Color, to end: Color, angle: Double = 90) -> VectorPaint {
        .linearGradient(stops: [GradientStop(offset: 0, color: start), GradientStop(offset: 1, color: end)], angle: angle)
    }

    func validate() throws {
        switch self {
        case .color(let color):
            try checkColor(color)
        case .linearGradient(let stops, let angle):
            guard angle.isFinite else { throw HokusaiError.invalidOption(name: "gradient angle", reason: "must be finite") }
            guard stops.count >= 2 else { throw HokusaiError.invalidOption(name: "gradient stops", reason: "needs at least two stops") }
            var previous = 0.0
            for stop in stops {
                guard stop.offset.isFinite, (0...1).contains(stop.offset), stop.offset >= previous else {
                    throw HokusaiError.invalidOption(name: "gradient stops", reason: "offsets must be in 0...1 and not decrease")
                }
                previous = stop.offset
                try checkColor(stop.color)
            }
        }
    }
}

/// An outline.
public struct VectorStroke: Sendable, Hashable {
    public var color: Color
    /// Line width in points, greater than zero.
    public var width: Double

    public init(color: Color, width: Double = 1) {
        self.color = color
        self.width = width
    }

    func validate() throws {
        try checkColor(color)
        guard width.isFinite, width > 0, width <= 1000 else {
            throw HokusaiError.invalidOption(name: "stroke width", reason: "must be a finite value from above 0 to 1000 points")
        }
    }
}

/// How a raster image fills its frame.
public enum VectorImageFit: Sendable, Hashable {
    /// The whole image is visible, scaled to fit and centred; the rest of the frame stays empty.
    case contain
    /// The frame is filled and the overflow is cut off, centred.
    case cover
    /// The image is stretched to the frame, ignoring its aspect ratio.
    case fill
}

/// The weight of a font, on the CSS scale.
public enum VectorFontWeight: Int, Sendable, Hashable, CaseIterable {
    case thin = 100
    case light = 300
    case regular = 400
    case medium = 500
    case semibold = 600
    case bold = 700
    case heavy = 800
    case black = 900
}

/// How lines of text are aligned within the text's width.
public enum VectorTextAlignment: Int, Sendable, Hashable, CaseIterable {
    case leading = 0
    case center = 1
    case trailing = 2
    /// Both edges are straight; the last line is leading.
    case justified = 3
}

/// Where a line that is too wide for the text's width is broken.
public enum VectorTextWrap: Int, Sendable, Hashable, CaseIterable {
    /// At word boundaries; a word wider than the line overflows.
    case word = 0
    /// At any character.
    case character = 1
    /// At word boundaries, and inside a word only when it does not fit on a line.
    case wordThenCharacter = 2
}

/// Typography of one text block.
///
/// The text is laid out by Pango and drawn as real text, so it can be selected, searched and
/// copied. `family` is a font family name resolved by fontconfig (or the system font service on
/// macOS); "sans", "serif" and "monospace" always resolve to something. A family that is not
/// installed falls back to the system default, and the PDF embeds whichever font was used.
public struct VectorTextStyle: Sendable, Hashable {
    public var family: String
    /// Font size in points, `1...1000`.
    public var size: Double
    public var weight: VectorFontWeight
    public var italic: Bool
    public var color: Color
    public var alignment: VectorTextAlignment
    public var wrap: VectorTextWrap
    /// Line height as a multiple of the font's natural line height, `0.5...5`.
    public var lineSpacing: Double

    public init(
        family: String = "sans",
        size: Double = 12,
        weight: VectorFontWeight = .regular,
        italic: Bool = false,
        color: Color = Color(red: 0, green: 0, blue: 0),
        alignment: VectorTextAlignment = .leading,
        wrap: VectorTextWrap = .word,
        lineSpacing: Double = 1
    ) {
        self.family = family
        self.size = size
        self.weight = weight
        self.italic = italic
        self.color = color
        self.alignment = alignment
        self.wrap = wrap
        self.lineSpacing = lineSpacing
    }

    func validate() throws {
        guard !family.isEmpty, !family.contains("\0") else {
            throw HokusaiError.invalidOption(name: "font family", reason: "must be a non-empty name")
        }
        guard size.isFinite, (1...1000).contains(size) else {
            throw HokusaiError.invalidOption(name: "font size", reason: "must be a finite value from 1 to 1000 points")
        }
        guard lineSpacing.isFinite, (0.5...5).contains(lineSpacing) else {
            throw HokusaiError.invalidOption(name: "line spacing", reason: "must be a finite value from 0.5 to 5")
        }
        try checkColor(color)
    }
}

/// The facts about a finished document.
public struct VectorOutputInfo: Sendable, Hashable {
    public let pageCount: Int
    /// The size of the PDF in bytes.
    public let byteCount: Int
}

/// A finished PDF and its facts.
public struct VectorOutput: Sendable, Hashable {
    public let data: Data
    public let info: VectorOutputInfo
}

/// Rejects a colour whose components are not finite values from 0 through 1.
func checkColor(_ color: Color) throws {
    let values = [color.red, color.green, color.blue, color.opacity]
    guard values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
        throw HokusaiError.invalidOption(name: "color", reason: "components must be finite values from 0 through 1")
    }
}
