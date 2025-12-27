import Foundation

/// Options for resize operations
public struct ResizeOptions: Sendable {
    /// Target width (nil to auto-calculate)
    public var width: Int?

    /// Target height (nil to auto-calculate)
    public var height: Int?

    /// How to fit the image
    public var fit: ResizeFit

    /// Position for cover/contain operations
    public var position: Position

    /// Interpolation kernel
    public var kernel: Kernel

    /// Don't enlarge if the input is smaller than the target
    public var withoutEnlargement: Bool

    /// Don't reduce if the input is larger than the target
    public var withoutReduction: Bool

    /// Background color for contain mode [R, G, B, A]
    public var background: [Double]?

    public init(
        width: Int? = nil,
        height: Int? = nil,
        fit: ResizeFit = .cover,
        position: Position = .center,
        kernel: Kernel = .lanczos3,
        withoutEnlargement: Bool = false,
        withoutReduction: Bool = false,
        background: [Double]? = nil
    ) {
        self.width = width
        self.height = height
        self.fit = fit
        self.position = position
        self.kernel = kernel
        self.withoutEnlargement = withoutEnlargement
        self.withoutReduction = withoutReduction
        self.background = background
    }
}

/// Options for format conversion and saving
public struct SaveOptions: Sendable {
    /// Output format
    public var format: ImageFormat?

    /// Quality (1-100, for lossy formats)
    public var quality: Int?

    /// Compression level (0-9, for PNG)
    public var compression: Int?

    /// Enable progressive/interlaced output
    public var progressive: Bool

    /// Strip metadata
    public var stripMetadata: Bool

    /// Enable lossless compression (for WebP)
    public var lossless: Bool

    /// Effort level (1-9, for AVIF/WebP)
    public var effort: Int?

    public init(
        format: ImageFormat? = nil,
        quality: Int? = nil,
        compression: Int? = nil,
        progressive: Bool = false,
        stripMetadata: Bool = false,
        lossless: Bool = false,
        effort: Int? = nil
    ) {
        self.format = format
        self.quality = quality
        self.compression = compression
        self.progressive = progressive
        self.stripMetadata = stripMetadata
        self.lossless = lossless
        self.effort = effort
    }
}

/// Options for crop operations
public struct CropOptions: Sendable {
    /// Left offset
    public var left: Int

    /// Top offset
    public var top: Int

    /// Width
    public var width: Int

    /// Height
    public var height: Int

    public init(left: Int, top: Int, width: Int, height: Int) {
        self.left = left
        self.top = top
        self.width = width
        self.height = height
    }
}
