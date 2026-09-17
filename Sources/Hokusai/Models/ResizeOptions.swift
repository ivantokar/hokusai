import Foundation

/// Legacy resize configuration used by the compatibility image-handle API.
///
/// New pipeline code should prefer ``Hokusai/resize(width:height:fit:position:kernel:withoutEnlargement:withoutReduction:background:)``,
/// whose labelled arguments use the 1.0 value types.
public struct ResizeOptions: Sendable {
    /// Requested output width, or `nil` to calculate it from height.
    public var width: Int?

    /// Requested output height, or `nil` to calculate it from width.
    public var height: Int?

    /// The aspect-ratio policy used when both dimensions are present.
    public var fit: ResizeFit

    /// The crop or anchor position for fitting modes that need one.
    public var position: Position

    /// The interpolation kernel used to resample pixels.
    public var kernel: Kernel

    /// Prevents enlarging an image that is already smaller than the target.
    public var withoutEnlargement: Bool

    /// Prevents reducing an image that is already larger than the target.
    public var withoutReduction: Bool

    /// Optional contain-mode background in 8-bit RGBA component order.
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

/// Legacy encoder settings used by synchronous `HokusaiImage` terminals.
///
/// The 1.0 pipeline uses ``OutputFormat`` and its typed option values instead.
public struct SaveOptions: Sendable {
    /// Explicit output format, or `nil` to infer it from the destination path.
    public var format: ImageFormat?

    /// Lossy-encoder quality from 1 through 100 where supported.
    public var quality: Int?

    /// PNG compression level from 0 through 9.
    public var compression: Int?

    /// Requests progressive JPEG or interlaced PNG output where supported.
    public var progressive: Bool

    /// Removes metadata that the selected encoder can omit.
    public var stripMetadata: Bool

    /// Selects lossless WebP encoding.
    public var lossless: Bool

    /// Encoder effort where the selected codec supports a speed-quality trade-off.
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

/// A rectangular region for the legacy crop API.
public struct CropOptions: Sendable {
    /// Zero-based horizontal offset from the image's left edge.
    public var left: Int

    /// Zero-based vertical offset from the image's top edge.
    public var top: Int

    /// Width of the extracted region in pixels.
    public var width: Int

    /// Height of the extracted region in pixels.
    public var height: Int

    public init(left: Int, top: Int, width: Int, height: Int) {
        self.left = left
        self.top = top
        self.width = width
        self.height = height
    }
}
