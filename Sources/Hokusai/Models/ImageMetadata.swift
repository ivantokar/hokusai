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
        size: Int? = nil
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
