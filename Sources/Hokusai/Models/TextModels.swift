import Foundation

/// The text of a ``Hokusai/text(_:layout:style:)`` source.
public enum TextContent: Sendable, Hashable, ExpressibleByStringLiteral {
    /// Literal text. Characters Pango would read as markup are escaped, so
    /// any caller string is safe to render.
    case plain(String)
    /// Pango markup, for mixed fonts, sizes and colours inside one text.
    ///
    /// This is [Pango markup](https://docs.gtk.org/Pango/pango_markup.html),
    /// not HTML or CSS. Invalid markup fails when the text is rendered.
    case markup(String)

    public init(stringLiteral value: String) {
        self = .plain(value)
    }

    var string: String {
        switch self {
        case .plain(let text), .markup(let text): text
        }
    }
}

/// How lines are broken when a width is given.
public enum TextWrap: Sendable, Hashable {
    /// Breaks between words.
    case word
    /// Breaks between characters.
    case character
    /// Breaks between words, and inside a word that is too long for a line.
    case wordCharacter
    /// Never breaks; text is clipped at the width.
    case none
}

/// Horizontal alignment of lines inside the text box.
public enum TextAlignment: String, Sendable {
    case left
    case center
    case right
}

/// The size of the text box.
public enum TextLayout: Sendable, Hashable {
    /// As large as the text needs. Lines break only at newlines.
    case natural
    /// Wraps lines to `width` pixels at the style's font size and DPI.
    case width(Int, wrap: TextWrap = .word)
    /// Picks the largest resolution at which the text fits `width` × `height`.
    ///
    /// The style's `dpi` is not used, and `lineHeight` must stay 1: libvips
    /// chooses the resolution after line spacing is fixed.
    case fit(width: Int, height: Int)
}

/// An outline drawn around the glyphs.
public struct TextStroke: Sendable, Hashable {
    public var color: Color
    /// Outline thickness in pixels, `0 < width ≤ 64`.
    public var width: Double

    public init(color: Color, width: Double) {
        self.color = color
        self.width = width
    }
}

/// A soft drop shadow behind the glyphs.
public struct TextShadow: Sendable, Hashable {
    public var offsetX: Int
    public var offsetY: Int
    /// Gaussian sigma of the shadow's softness in pixels, `0...64`.
    public var blur: Double
    /// Shadow colour; its opacity is the shadow's opacity.
    public var color: Color

    public init(offsetX: Int, offsetY: Int, blur: Double = 1.2, color: Color = Color(red: 0, green: 0, blue: 0, opacity: 0.5)) {
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.blur = blur
        self.color = color
    }
}

/// Typography for generated text.
public struct TextStyle: Sendable, Hashable {
    /// Pango font family and style without a size, for example `"Helvetica Bold"`.
    public var font: String
    /// A local TTF or OTF file made available to `font` for this render.
    /// Needs a libvips built with fontconfig. libvips reports a file it cannot
    /// load, or a build without fontconfig, only as a warning and then renders
    /// with the named `font`, so this support is not part of
    /// ``RuntimeCapabilities`` and a wrong file is not an error. Hokusai checks
    /// that the file exists and is readable.
    public var fontFile: URL?
    /// Font size in points at `dpi`, `1...2000`.
    public var fontSize: Int
    public var color: Color
    public var alignment: TextAlignment
    /// Stretches wrapped lines to the full width.
    public var justify: Bool
    /// Line pitch as a multiple of the font's natural line height; `1` is the
    /// font's own spacing. Range `0.5...5`.
    public var lineHeight: Double
    /// Rendering resolution, `1...2400`. Ignored by `.fit` layouts.
    public var dpi: Int
    public var stroke: TextStroke?
    public var shadow: TextShadow?
    /// Clockwise rotation of the text, in degrees.
    public var rotation: Double

    public init(
        font: String = "sans",
        fontFile: URL? = nil,
        fontSize: Int = 24,
        color: Color = Color(red: 0, green: 0, blue: 0),
        alignment: TextAlignment = .left,
        justify: Bool = false,
        lineHeight: Double = 1,
        dpi: Int = 72,
        stroke: TextStroke? = nil,
        shadow: TextShadow? = nil,
        rotation: Double = 0
    ) {
        self.font = font
        self.fontFile = fontFile
        self.fontSize = fontSize
        self.color = color
        self.alignment = alignment
        self.justify = justify
        self.lineHeight = lineHeight
        self.dpi = dpi
        self.stroke = stroke
        self.shadow = shadow
        self.rotation = rotation
    }
}

/// A fully described text source: what the evaluator renders.
struct TextSource: Sendable, Equatable {
    var content: TextContent
    var layout: TextLayout
    var style: TextStyle

    /// Rejects values that can be known to be invalid without rendering.
    func validate() throws {
        func fail(_ name: String, _ reason: String) -> HokusaiError { .invalidOption(name: name, reason: reason) }

        guard !content.string.isEmpty else { throw fail("text", "must not be empty") }
        let font = style.font.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !font.isEmpty else { throw fail("font", "must not be empty") }
        guard !font.contains("/"), !font.lowercased().hasSuffix(".ttf"), !font.lowercased().hasSuffix(".otf") else {
            throw fail("font", "is a family name; pass a font file as fontFile")
        }
        if let file = style.fontFile, !file.isFileURL { throw fail("fontFile", "must be a local file URL") }
        guard (1...2000).contains(style.fontSize) else { throw fail("fontSize", "must be from 1 through 2000") }
        guard (1...2400).contains(style.dpi) else { throw fail("dpi", "must be from 1 through 2400") }
        guard style.lineHeight.isFinite, (0.5...5).contains(style.lineHeight) else {
            throw fail("lineHeight", "must be from 0.5 through 5")
        }
        guard style.rotation.isFinite else { throw fail("rotation", "must be finite") }
        _ = try style.color.rgba8()

        switch layout {
        case .natural: break
        case .width(let width, _):
            guard (1...maximumNativeCoordinate).contains(width) else { throw fail("width", "must be a positive pixel count") }
        case .fit(let width, let height):
            guard (1...maximumNativeCoordinate).contains(width), (1...maximumNativeCoordinate).contains(height) else {
                throw fail("fit", "width and height must be positive pixel counts")
            }
            guard style.lineHeight == 1 else { throw fail("lineHeight", "must be 1 with a fit layout") }
        }
        if let stroke = style.stroke {
            guard stroke.width.isFinite, stroke.width > 0, stroke.width <= 64 else {
                throw fail("stroke.width", "must be greater than 0 and at most 64")
            }
            _ = try stroke.color.rgba8()
        }
        if let shadow = style.shadow {
            guard shadow.blur.isFinite, (0...64).contains(shadow.blur) else { throw fail("shadow.blur", "must be from 0 through 64") }
            guard (-10_000...10_000).contains(shadow.offsetX), (-10_000...10_000).contains(shadow.offsetY) else {
                throw fail("shadow.offset", "must be within ±10000 pixels")
            }
            _ = try shadow.color.rgba8()
        }
    }
}
