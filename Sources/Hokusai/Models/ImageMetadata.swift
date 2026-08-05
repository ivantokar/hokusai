import Foundation

/// PURPOSE: Metadata information about an image
public struct ImageMetadata: Sendable {
    /// PURPOSE: Image width in pixels
    public let width: Int

    /// PURPOSE: Image height in pixels
    public let height: Int

    /// PURPOSE: Number of color channels
    public let channels: Int

    /// PURPOSE: Image format
    public let format: ImageFormat?

    /// PURPOSE: Color space
    public let space: String?

    /// PURPOSE: Whether the image has an alpha channel
    public let hasAlpha: Bool

    /// PURPOSE: Image orientation (EXIF)
    public let orientation: Int?

    /// PURPOSE: Density in DPI
    public let density: Double?

    /// PURPOSE: Number of pages (for multi-page formats like GIF, PDF)
    public let pages: Int?

    /// PURPOSE: File size in bytes (if available)
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
    public let horizontal: Double
    public let vertical: Double

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
