import Foundation

/// Portable RGBA colour used by resize, canvas, and compositing operations.
public struct Color: Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let opacity: Double

    /// Creates a colour from finite, normalized components in the range 0...1.
    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    public static let transparent = Color(red: 0, green: 0, blue: 0, opacity: 0)
    public static let white = Color(red: 1, green: 1, blue: 1)

    /// Validates the normalized components and converts them to libvips RGBA bytes.
    internal func rgba8() throws -> [Double] {
        let values = [red, green, blue, opacity]
        guard values.allSatisfy(\.isFinite), values.allSatisfy({ (0...1).contains($0) }) else {
            throw HokusaiError.invalidOption(name: "color", reason: "components must be finite values from 0 through 1")
        }
        return [red * 255, green * 255, blue * 255, opacity * 255]
    }
}

/// A pixel size used for canvas operations.
public struct ImageSize: Hashable, Sendable {
    /// Requested canvas width in pixels.
    public let width: Int
    /// Requested canvas height in pixels.
    public let height: Int

    /// Creates a typed pixel size for canvas operations.
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// Anchor used to place an image inside an expanded canvas.
public enum CanvasAnchor: Sendable {
    case center, north, south, east, west
    case northWest, northEast, southWest, southEast
}

/// Placement or content-aware crop strategy used by pipeline resize operations.
public enum ResizePosition: Sendable {
    case center, north, south, east, west
    case northWest, northEast, southWest, southEast
    case attention, entropy
}

/// Interpolation kernel used when pipeline resize samples pixels.
public enum ResizeKernel: Sendable {
    case nearest, linear, cubic, mitchell, lanczos2, lanczos3
}

/// Portable colour spaces supported by the first Hokusai pipeline release.
public enum ColorSpace: Sendable, Equatable {
    case sRGB
    case grayscale
}

/// Typed output encoder configuration.
public enum OutputFormat: Sendable {
    case jpeg(JPEGOptions = .init())
    case png(PNGOptions = .init())
    case webp(WebPOptions = .init())
    case avif(AVIFOptions = .init())
    case pdf(PDFOptions = .init())

    /// The metadata format corresponding to this encoder choice.
    public var imageFormat: ImageFormat {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        case .webp: .webp
        case .avif: .avif
        case .pdf: .pdf
        }
    }
}

/// JPEG encoder settings. Quality uses libvips' 0...100 convention.
public struct JPEGOptions: Sendable {
    public var quality: Int
    public var progressive: Bool
    public init(quality: Int = 80, progressive: Bool = false) { self.quality = quality; self.progressive = progressive }
}
/// PNG encoder settings. Compression level follows libvips' 0...9 convention.
public struct PNGOptions: Sendable {
    public var compressionLevel: Int
    public var progressive: Bool
    public init(compressionLevel: Int = 6, progressive: Bool = false) { self.compressionLevel = compressionLevel; self.progressive = progressive }
}
/// WebP encoder settings for lossy/lossless output and encoder effort.
public struct WebPOptions: Sendable {
    public var quality: Int
    public var effort: Int
    public var lossless: Bool
    public init(quality: Int = 80, effort: Int = 4, lossless: Bool = false) { self.quality = quality; self.effort = effort; self.lossless = lossless }
}
/// AVIF encoder settings for lossy/lossless output and encoder effort.
public struct AVIFOptions: Sendable {
    public var quality: Int
    public var effort: Int
    public var lossless: Bool
    public init(quality: Int = 50, effort: Int = 4, lossless: Bool = false) { self.quality = quality; self.effort = effort; self.lossless = lossless }
}

/// Encoded bytes and the stable facts measured from the evaluated output.
public struct Output: Sendable {
    public let data: Data
    public let info: OutputInfo
}

/// Facts about an evaluated output.
///
/// `width` and `height` are the pixel dimensions of the encoded image. For PDF
/// they are the pixels of the embedded raster (after any downsampling), and
/// ``pdf`` carries the physical page geometry.
public struct OutputInfo: Sendable, Equatable {
    public let format: ImageFormat
    public let width: Int
    public let height: Int
    public let size: Int

    /// Page facts when `format` is PDF; `nil` for every other format.
    public let pdf: PDFOutputDetails?

    init(format: ImageFormat, width: Int, height: Int, size: Int, pdf: PDFOutputDetails? = nil) {
        self.format = format
        self.width = width
        self.height = height
        self.size = size
        self.pdf = pdf
    }
}

/// A layer composited over a pipeline in the supplied order.
public struct CompositeLayer: Sendable {
    internal let source: Hokusai
    public let x: Int
    public let y: Int
    public let blend: BlendMode
    public let opacity: Double

    /// Creates a layer from another immutable pipeline.
    public init(_ image: Hokusai, x: Int = 0, y: Int = 0, blend: BlendMode = .over, opacity: Double = 1) {
        self.source = image
        self.x = x
        self.y = y
        self.blend = blend
        self.opacity = opacity
    }

    /// Decodes in-memory data into a pipeline layer.
    public init(data: Data, x: Int = 0, y: Int = 0, blend: BlendMode = .over, opacity: Double = 1) throws {
        self.init(try Hokusai(data: data), x: x, y: y, blend: blend, opacity: opacity)
    }
}

internal extension ResizePosition {
    /// Maps pipeline placement names onto the legacy operation's vocabulary.
    var legacyPosition: Position {
        switch self {
        case .center: .center
        case .north: .top
        case .south: .bottom
        case .east: .right
        case .west: .left
        case .northWest: .topLeft
        case .northEast: .topRight
        case .southWest: .bottomLeft
        case .southEast: .bottomRight
        case .attention: .attention
        case .entropy: .entropy
        }
    }
}

internal extension CanvasAnchor {
    /// Calculates the top-left offset for the selected anchor inside a canvas.
    func offset(imageWidth: Int, imageHeight: Int, canvasWidth: Int, canvasHeight: Int) -> (x: Int, y: Int) {
        let horizontal = (canvasWidth - imageWidth) / 2
        let vertical = (canvasHeight - imageHeight) / 2
        switch self {
        case .center: return (horizontal, vertical)
        case .north: return (horizontal, 0)
        case .south: return (horizontal, canvasHeight - imageHeight)
        case .east: return (canvasWidth - imageWidth, vertical)
        case .west: return (0, vertical)
        case .northWest: return (0, 0)
        case .northEast: return (canvasWidth - imageWidth, 0)
        case .southWest: return (0, canvasHeight - imageHeight)
        case .southEast: return (canvasWidth - imageWidth, canvasHeight - imageHeight)
        }
    }
}

internal extension ResizeKernel {
    /// Maps typed pipeline kernels onto the legacy libvips operation enum.
    var legacyKernel: Kernel {
        switch self {
        case .nearest: .nearest
        case .linear: .linear
        case .cubic: .cubic
        case .mitchell: .mitchell
        case .lanczos2: .lanczos2
        case .lanczos3: .lanczos3
        }
    }
}
