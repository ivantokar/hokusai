import Foundation

/// Options controlling how an encoded source is opened.
public struct InputOptions: Sendable {
    /// The point at which decoder warnings become errors.
    public var failOn: DecodeFailureLevel
    /// Optional zero-based page to load from a multi-page input.
    public var page: Int?
    /// Optional page count to load from a multi-page input.
    public var pages: Int?

    public init(failOn: DecodeFailureLevel = .warning, page: Int? = nil, pages: Int? = nil) {
        self.failOn = failOn
        self.page = page
        self.pages = pages
    }
}

/// Decoder failure policy. Loader-specific support is reported as unsupported.
public enum DecodeFailureLevel: Sendable, Equatable {
    case none
    case warning
    case error
}

/// Portable RGBA colour used by resize, canvas, and compositing operations.
public struct Color: Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let opacity: Double

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    public static let transparent = Color(red: 0, green: 0, blue: 0, opacity: 0)
    public static let white = Color(red: 1, green: 1, blue: 1)

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
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public enum CanvasAnchor: Sendable {
    case center, north, south, east, west
    case northWest, northEast, southWest, southEast
}

public enum ResizePosition: Sendable {
    case center, north, south, east, west
    case northWest, northEast, southWest, southEast
    case attention, entropy
}

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

public struct JPEGOptions: Sendable { public var quality: Int; public var progressive: Bool; public init(quality: Int = 80, progressive: Bool = false) { self.quality = quality; self.progressive = progressive } }
public struct PNGOptions: Sendable { public var compressionLevel: Int; public var progressive: Bool; public init(compressionLevel: Int = 6, progressive: Bool = false) { self.compressionLevel = compressionLevel; self.progressive = progressive } }
public struct WebPOptions: Sendable { public var quality: Int; public var effort: Int; public var lossless: Bool; public init(quality: Int = 80, effort: Int = 4, lossless: Bool = false) { self.quality = quality; self.effort = effort; self.lossless = lossless } }
public struct AVIFOptions: Sendable { public var quality: Int; public var effort: Int; public var lossless: Bool; public init(quality: Int = 50, effort: Int = 4, lossless: Bool = false) { self.quality = quality; self.effort = effort; self.lossless = lossless } }

/// Page geometry for Cairo-backed PDF output, expressed in PostScript points.
public enum PDFPageSize: Sendable, Equatable {
    /// Size the page from the raster dimensions at the configured DPI.
    case image
    case a4
    case letter
    case points(width: Double, height: Double)
}

/// Options for rendering the current pipeline as a one-page PDF document.
public struct PDFOptions: Sendable, Equatable {
    public var pageSize: PDFPageSize
    /// Raster resolution used only when `pageSize` is `.image`.
    public var dpi: Double

    public init(pageSize: PDFPageSize = .image, dpi: Double = 72) {
        self.pageSize = pageSize
        self.dpi = dpi
    }
}

/// Encoded output and its stable properties.
public struct Output: Sendable {
    public let data: Data
    public let info: OutputInfo
}

public struct OutputInfo: Sendable, Equatable {
    public let format: ImageFormat
    public let width: Int
    public let height: Int
    public let size: Int
}

/// A layer composited over a pipeline in the supplied order.
public struct CompositeLayer: Sendable {
    internal let source: Hokusai
    public let x: Int
    public let y: Int
    public let blend: BlendMode
    public let opacity: Double

    public init(_ image: Hokusai, x: Int = 0, y: Int = 0, blend: BlendMode = .over, opacity: Double = 1) {
        self.source = image
        self.x = x
        self.y = y
        self.blend = blend
        self.opacity = opacity
    }

    public init(data: Data, x: Int = 0, y: Int = 0, blend: BlendMode = .over, opacity: Double = 1) throws {
        self.init(try Hokusai(data: data), x: x, y: y, blend: blend, opacity: opacity)
    }
}

internal extension ResizePosition {
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

internal extension OutputFormat {
    var legacySaveOptions: SaveOptions {
        switch self {
        case .jpeg(let options):
            return SaveOptions(format: .jpeg, quality: options.quality, progressive: options.progressive)
        case .png(let options):
            return SaveOptions(format: .png, compression: options.compressionLevel, progressive: options.progressive)
        case .webp(let options):
            return SaveOptions(format: .webp, quality: options.quality, lossless: options.lossless, effort: options.effort)
        case .avif(let options):
            return SaveOptions(format: .avif, quality: options.quality, lossless: options.lossless, effort: options.effort)
        case .pdf:
            return SaveOptions(format: .pdf)
        }
    }
}
