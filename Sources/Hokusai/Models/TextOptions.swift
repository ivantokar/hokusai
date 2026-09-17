import Foundation

/// Styling and layout options for libvips/Pango text rendering.
///
/// Colours use 8-bit RGBA component order. This compatibility-oriented model
/// is intentionally broad; new typography work should evolve it through a
/// dedicated typed API rather than adding unvalidated options.
public struct TextOptions: Sendable {
    /// Pango font family or description, for example `"Helvetica Bold"`.
    public var font: String

    /// Optional TTF or OTF file path; `font` still supplies family and style.
    public var fontFile: String?

    /// Font size in points at the configured DPI.
    public var fontSize: Int

    /// Foreground colour in 8-bit RGBA component order.
    public var color: [Double]

    /// Horizontal alignment when a width constraint is supplied.
    public var align: TextAlignment

    /// Text-rendering resolution in dots per inch.
    public var dpi: Int

    /// Optional wrapping width in pixels.
    public var width: Int?

    /// Optional maximum text height in pixels.
    public var height: Int?

    // MARK: - Advanced Text Features (best-effort via libvips)

    /// Optional outline colour in 8-bit RGBA component order.
    public var strokeColor: [Double]?

    /// Optional outline width in pixels.
    public var strokeWidth: Double?

    /// Optional shadow offset in pixels.
    public var shadowOffset: (x: Double, y: Double)?

    /// Optional shadow colour in 8-bit RGBA component order.
    public var shadowColor: [Double]?

    /// Optional shadow opacity from 0 through 1.
    public var shadowOpacity: Double?

    /// Optional additional letter spacing in pixels.
    public var kerning: Double?

    /// Optional line-spacing multiplier, such as `1.5` for 150% spacing.
    public var lineSpacing: Double?

    /// Optional gravity used by the semantic-position drawing overload.
    public var gravity: TextGravity?

    /// Whether libvips should antialias text edges.
    public var antialiasing: Bool

    /// Optional clockwise rotation in degrees.
    public var rotation: Double?

    public init(
        font: String = "sans",
        fontFile: String? = nil,
        fontSize: Int = 24,
        color: [Double] = [0, 0, 0, 255],  // Black
        align: TextAlignment = .left,
        dpi: Int = 72,
        width: Int? = nil,
        height: Int? = nil,
        strokeColor: [Double]? = nil,
        strokeWidth: Double? = nil,
        shadowOffset: (x: Double, y: Double)? = nil,
        shadowColor: [Double]? = nil,
        shadowOpacity: Double? = nil,
        kerning: Double? = nil,
        lineSpacing: Double? = nil,
        gravity: TextGravity? = nil,
        antialiasing: Bool = true,
        rotation: Double? = nil
    ) {
        self.font = font
        self.fontFile = fontFile
        self.fontSize = fontSize
        self.color = color
        self.align = align
        self.dpi = dpi
        self.width = width
        self.height = height
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.shadowOffset = shadowOffset
        self.shadowColor = shadowColor
        self.shadowOpacity = shadowOpacity
        self.kerning = kerning
        self.lineSpacing = lineSpacing
        self.gravity = gravity
        self.antialiasing = antialiasing
        self.rotation = rotation
    }
}

/// Horizontal text alignment for constrained text layout.
public enum TextAlignment: String, Sendable {
    case left
    case center
    case right
}

/// A semantic position for placing text inside an image.
public enum TextGravity: String, Sendable {
    case center
    case north
    case south
    case east
    case west
    case northEast
    case northWest
    case southEast
    case southWest
}
