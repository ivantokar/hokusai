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

    /// Creates a colour from 8-bit sRGB components, the way CSS and design
    /// tools write them: `Color.sRGB8(red: 255, green: 64, blue: 0)`.
    public static func sRGB8(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) -> Color {
        Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: Double(alpha) / 255)
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

/// A compass point used to place one rectangle inside another: an image in
/// an expanded canvas, or a layer on a base image.
public enum Gravity: Sendable {
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
///
/// `mks2013` and `mks2021` are the Magic Kernel Sharp kernels. They need
/// libvips 8.17 or newer, which is above Hokusai's 8.16 baseline, so using
/// one on an older build throws `unsupported` when the step is added.
public enum ResizeKernel: Sendable {
    case nearest, linear, cubic, mitchell, lanczos2, lanczos3, mks2013, mks2021
}

/// How a canvas or transform fills pixels outside the source image.
public enum ExtendMode: Sendable, Equatable {
    /// Fills with a colour. Use ``Color/transparent`` for transparent padding.
    case background(Color)
    /// Repeats the nearest edge pixel outwards.
    case copy
    /// Tiles the image.
    case `repeat`
    /// Tiles the image, mirroring every other tile.
    case mirror
}

/// Pixel interpolation used by resampling transforms such as ``Hokusai/rotate(by:background:interpolation:)``.
public enum Interpolation: String, Sendable, CaseIterable {
    case nearest, bilinear, bicubic, lbb, nohalo, vsqbs
}

/// Accuracy of the Gaussian mask used by ``Hokusai/blur(sigma:precision:minAmplitude:)``.
public enum BlurPrecision: String, Sendable, CaseIterable {
    /// Integer arithmetic: fastest, and exact for 8-bit images.
    case integer
    /// Floating-point arithmetic.
    case float
    /// A fast approximation of the mask.
    case approximate
}

/// Controls for ``Hokusai/sharpen(_:)``, an unsharp mask on luminance.
///
/// The defaults are libvips' own, with a `sigma` of 1. Edges steeper than
/// `threshold` count as jagged and are sharpened by `jagged`; flatter areas
/// by `flat`. `maxBrightening` and `maxDarkening` cap how far a pixel may move.
public struct SharpenOptions: Hashable, Sendable {
    /// Radius of the Gaussian used to find detail, in pixels. Must be above zero.
    public var sigma: Double
    /// Sharpening strength applied to flat areas (libvips `m1`).
    public var flat: Double
    /// Sharpening strength applied to jagged edges (libvips `m2`).
    public var jagged: Double
    /// Difference that separates flat areas from jagged edges (libvips `x1`).
    public var threshold: Double
    /// The most a pixel may brighten (libvips `y2`).
    public var maxBrightening: Double
    /// The most a pixel may darken (libvips `y3`).
    public var maxDarkening: Double

    public init(
        sigma: Double = 1,
        flat: Double = 0,
        jagged: Double = 3,
        threshold: Double = 2,
        maxBrightening: Double = 10,
        maxDarkening: Double = 20
    ) {
        self.sigma = sigma
        self.flat = flat
        self.jagged = jagged
        self.threshold = threshold
        self.maxBrightening = maxBrightening
        self.maxDarkening = maxDarkening
    }

    func validate() throws {
        guard sigma.isFinite, sigma > 0, sigma <= 10_000 else {
            throw HokusaiError.invalidOption(name: "sigma", reason: "must be a finite value above zero")
        }
        let others: [(String, Double)] = [
            ("flat", flat), ("jagged", jagged), ("threshold", threshold),
            ("maxBrightening", maxBrightening), ("maxDarkening", maxDarkening),
        ]
        for (name, value) in others where !(value.isFinite && value >= 0 && value <= 1_000_000) {
            throw HokusaiError.invalidOption(name: name, reason: "must be a finite value from 0 to 1000000")
        }
    }
}

/// A 2×2 linear transform: `x' = a·x + b·y`, `y' = c·x + d·y`.
public struct AffineMatrix: Hashable, Sendable {
    public var a: Double
    public var b: Double
    public var c: Double
    public var d: Double

    public init(a: Double, b: Double, c: Double, d: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
    }

    public static let identity = AffineMatrix(a: 1, b: 0, c: 0, d: 1)
}

/// A fractional pixel offset used by ``Hokusai/affine(_:inputOffset:outputOffset:outputArea:edges:interpolation:)``.
public struct AffineOffset: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = AffineOffset(x: 0, y: 0)
}

/// The output rectangle of an affine transform, in output pixel coordinates.
public struct AffineArea: Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Portable colour spaces supported by the first Hokusai pipeline release.
public enum ColorSpace: Sendable, Equatable {
    case sRGB
    case grayscale
}

/// Typed output encoder configuration.
public enum OutputFormat: Sendable, Equatable {
    case jpeg(JPEGOptions = .init())
    case png(PNGOptions = .init())
    case webp(WebPOptions = .init())
    case avif(AVIFOptions = .init())
    case heif(HEIFOptions = .init())
    case tiff(TIFFOptions = .init())
    case gif(GIFOptions = .init())
    case pdf(PDFOptions = .init())

    /// The metadata format corresponding to this encoder choice.
    public var imageFormat: ImageFormat {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        case .webp: .webp
        case .avif: .avif
        case .heif: .heif
        case .tiff: .tiff
        case .gif: .gif
        case .pdf: .pdf
        }
    }
}

/// Encoded bytes and the stable facts measured from the evaluated output.
public struct Output: Sendable, Equatable {
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
    /// The encoded size in bytes. ``width`` and ``height`` are pixels.
    public let byteCount: Int

    /// Page facts when `format` is PDF; `nil` for every other format.
    public let pdf: PDFOutputDetails?

    init(format: ImageFormat, width: Int, height: Int, byteCount: Int, pdf: PDFOutputDetails? = nil) {
        self.format = format
        self.width = width
        self.height = height
        self.byteCount = byteCount
        self.pdf = pdf
    }
}

internal extension Gravity {
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
