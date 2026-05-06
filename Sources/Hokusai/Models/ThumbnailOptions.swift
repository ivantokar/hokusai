import Foundation

/// Cropping strategy for thumbnail operations.
///
/// When both `width` and `height` are constrained and the source aspect ratio
/// does not match the target, libvips must either pad, letterbox, or crop.
/// This enum selects the cropping strategy.
public enum ThumbnailCrop: Sendable {
    /// No crop: preserve aspect ratio and fit the image inside the target bounds.
    /// One dimension may be smaller than requested.
    case none
    /// Crop to exact dimensions, centered. Fast; no content-aware analysis.
    case centre
    /// Crop to exact dimensions using attention-based focus detection.
    /// libvips analyses the image to find the most visually important region.
    case attention
    /// Crop to exact dimensions using entropy maximisation.
    /// libvips finds the region with the most visual information.
    case entropy
}

/// Options for thumbnail operations via ``Hokusai/thumbnail(from:width:options:)``
/// and ``HokusaiImage/thumbnail(width:options:)``.
///
/// ## Choosing between thumbnail and resize
///
/// Use ``Hokusai/thumbnail(from:width:options:)`` (the static entry point) when:
/// - You are starting from a file path or raw buffer.
/// - The source is a large JPEG, TIFF, or HEIF and you want a much smaller output.
/// - You want libvips to apply EXIF auto-rotation automatically.
///
/// The file-path variant calls `vips_thumbnail()` internally, which reads only
/// enough of the source to produce the requested output size. For JPEG this
/// means the JPEG decoder shrinks the image by 2×, 4×, or 8× during decode,
/// so the convolution kernel operates on a much smaller intermediate. For PNG
/// and most WebP there is no shrink-on-load; speed is similar to
/// `resize`.
///
/// Use ``HokusaiImage/resize(width:height:options:)`` when:
/// - You need explicit control over the interpolation kernel.
/// - You need fit modes like ``ResizeFit/contain`` or ``ResizeFit/outside``.
/// - The image is already loaded and you want consistent kernel behaviour.
public struct ThumbnailOptions: Sendable {
    /// Optional height constraint. `nil` means only the width bound applies
    /// and height is calculated to preserve the source aspect ratio.
    public var height: Int?

    /// Cropping strategy when both width and height are specified and the
    /// source aspect ratio does not match. Default is ``ThumbnailCrop/none``
    /// (fit inside, no crop).
    public var crop: ThumbnailCrop

    /// When `true`, skip EXIF-based auto-rotation.
    /// Default is `false`: the thumbnail is auto-rotated to match EXIF
    /// orientation, which is the expected behaviour for photos.
    public var noRotate: Bool

    public init(
        height: Int? = nil,
        crop: ThumbnailCrop = .none,
        noRotate: Bool = false
    ) {
        self.height = height
        self.crop = crop
        self.noRotate = noRotate
    }
}
