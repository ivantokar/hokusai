import Foundation

/// Options for text rendering
public struct TextOptions: Sendable {
    /// Font family name or Pango font description (e.g., "Arial", "Helvetica Bold")
    /// Backward-compatible: this may also be a path to a TTF/OTF font file.
    public var font: String

    /// Optional explicit font file path (TTF/OTF). When set, `font` remains the family/style descriptor.
    public var fontFile: String?

    /// Font size in points
    public var fontSize: Int

    /// Text color [R, G, B, A] (0-255)
    public var color: [Double]

    /// Horizontal alignment
    public var align: TextAlignment

    /// DPI for text rendering
    public var dpi: Int

    /// Text width for wrapping (nil = no wrapping)
    public var width: Int?

    /// Text height limit
    public var height: Int?

    // MARK: - Advanced Text Features (best-effort via libvips)

    /// Stroke (outline) color [R, G, B, A] (0-255)
    public var strokeColor: [Double]?

    /// Stroke (outline) width in pixels
    public var strokeWidth: Double?

    /// Shadow offset (x, y) in pixels
    public var shadowOffset: (x: Double, y: Double)?

    /// Shadow color [R, G, B, A] (0-255)
    public var shadowColor: [Double]?

    /// Shadow opacity (0.0-1.0)
    public var shadowOpacity: Double?

    /// Letter spacing (kerning) in pixels
    public var kerning: Double?

    /// Line spacing multiplier (e.g., 1.5 for 150% spacing)
    public var lineSpacing: Double?

    /// Text gravity for positioning
    public var gravity: TextGravity?

    /// Enable anti-aliasing (default: true)
    public var antialiasing: Bool

    /// Rotation angle in degrees
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

/// Text alignment options
public enum TextAlignment: String, Sendable {
    case left
    case center
    case right
}

/// Text gravity for image positioning
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
