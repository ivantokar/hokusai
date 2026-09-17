import Foundation

/// A typed snapshot of the current image's dimensions, pixel model, and embedded metadata.
public struct ImageMetadata: Sendable {
    /// Image width in pixels.
    public let width: Int

    /// Image height in pixels.
    public let height: Int

    /// Number of colour channels in each pixel.
    public let channels: Int

    /// Decoded image format when libvips can identify it.
    public let format: ImageFormat?

    /// Backend-reported colour space name, when available.
    public let space: String?

    /// Whether the image has an alpha channel.
    public let hasAlpha: Bool

    /// EXIF orientation value, when present.
    public let orientation: Int?

    /// Legacy single density value in dots per inch.
    public let density: Double?

    /// Number of pages for a multi-page image, when available.
    public let pages: Int?

    /// Source size in bytes, when the decoder reports it.
    public let size: Int?

    /// Typed interpretation of the image colour space when Hokusai recognises it.
    public let colorSpace: ColorSpace?

    /// Horizontal and vertical image density in dots per inch.
    public let densityXY: ImageDensity?

    /// Pixel height of each page for multi-page images.
    public let pageHeight: Int?

    /// Whether the source contains more than one page/frame.
    public let isAnimated: Bool

    /// Embedded metadata blocks, copied from libvips when present.
    public let exif: Data?
    public let iccProfile: Data?
    public let xmp: Data?

    /// Creates metadata explicitly, which is useful when adapting another image source.
    public init(
        width: Int,
        height: Int,
        channels: Int,
        format: ImageFormat? = nil,
        space: String? = nil,
        hasAlpha: Bool = false,
        orientation: Int? = nil,
        density: Double? = nil,
        pages: Int? = nil,
        size: Int? = nil,
        colorSpace: ColorSpace? = nil,
        densityXY: ImageDensity? = nil,
        pageHeight: Int? = nil,
        isAnimated: Bool = false,
        exif: Data? = nil,
        iccProfile: Data? = nil,
        xmp: Data? = nil
    ) {
        self.width = width
        self.height = height
        self.channels = channels
        self.format = format
        self.space = space
        self.hasAlpha = hasAlpha
        self.orientation = orientation
        self.density = density
        self.pages = pages
        self.size = size
        self.colorSpace = colorSpace
        self.densityXY = densityXY
        self.pageHeight = pageHeight
        self.isAnimated = isAnimated
        self.exif = exif
        self.iccProfile = iccProfile
        self.xmp = xmp
    }
}

/// Image pixel density expressed in dots per inch.
public struct ImageDensity: Sendable, Equatable {
    /// Horizontal resolution in dots per inch.
    public let horizontal: Double
    /// Vertical resolution in dots per inch.
    public let vertical: Double

    /// Creates an anisotropic pixel-density value.
    public init(horizontal: Double, vertical: Double) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
}

extension ImageMetadata: CustomStringConvertible {
    public var description: String {
        var parts: [String] = ["\(width)x\(height)"]

        if let format = format {
            parts.append(format.rawValue.uppercased())
        }

        parts.append("\(channels) channels")

        if hasAlpha {
            parts.append("alpha")
        }

        if let space = space {
            parts.append(space)
        }

        return parts.joined(separator: ", ")
    }
}
