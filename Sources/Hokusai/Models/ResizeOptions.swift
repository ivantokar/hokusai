import Foundation

/// PURPOSE: Options for resize operations
public struct ResizeOptions: Sendable {
    /// PURPOSE: Target width (nil to auto-calculate)
    public var width: Int?

    /// PURPOSE: Target height (nil to auto-calculate)
    public var height: Int?

    /// PURPOSE: How to fit the image
    public var fit: ResizeFit

    /// PURPOSE: Position for cover/contain operations
    public var position: Position

    /// PURPOSE: Interpolation kernel
    public var kernel: Kernel

    /// PURPOSE: Don't enlarge if the input is smaller than the target
    public var withoutEnlargement: Bool

    /// PURPOSE: Don't reduce if the input is larger than the target
    public var withoutReduction: Bool

    /// PURPOSE: Background color for contain mode [R, G, B, A]
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

/// PURPOSE: Options for format conversion and saving
public struct SaveOptions: Sendable {
    /// PURPOSE: Output format
    public var format: ImageFormat?

    /// PURPOSE: Quality (1-100, for lossy formats)
    public var quality: Int?

    /// PURPOSE: Compression level (0-9, for PNG)
    public var compression: Int?

    /// PURPOSE: Enable progressive/interlaced output
    public var progressive: Bool

    /// PURPOSE: Strip metadata
    public var stripMetadata: Bool

    /// PURPOSE: Enable lossless compression (for WebP)
    public var lossless: Bool

    /// PURPOSE: Effort level (1-9, for AVIF/WebP)
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

/// PURPOSE: Options for crop operations
public struct CropOptions: Sendable {
    /// PURPOSE: Left offset
    public var left: Int

    /// PURPOSE: Top offset
    public var top: Int

    /// PURPOSE: Width
    public var width: Int

    /// PURPOSE: Height
    public var height: Int

    public init(left: Int, top: Int, width: Int, height: Int) {
        self.left = left
        self.top = top
        self.width = width
        self.height = height
    }
}
