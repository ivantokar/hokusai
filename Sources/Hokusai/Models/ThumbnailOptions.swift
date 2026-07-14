import Foundation

/// Cropping strategy for thumbnail operations.
///
/// When both `width` and `height` are constrained and the source aspect ratio
/// does not match the target, libvips must either fit inside the bounds or
/// crop. This enum selects the cropping strategy.
public enum ThumbnailCrop: Sendable, CaseIterable {
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
/// - The source format has shrink-on-load support (JPEG, WebP, TIFF pyramids,
///   HEIF, PDF/SVG) and you want a much smaller output.
/// - You want libvips to apply EXIF auto-rotation automatically.
///
/// The file-path variant calls `vips_thumbnail()` internally. It reads the
/// image header, computes the shrink factor, and re-opens the source with
/// that factor passed to the loader. For JPEG the decoder shrinks by 2×, 4×,
/// or 8× during decode; for WebP libwebp scales during decode; TIFF pyramids
/// select a level; HEIF may use the embedded thumbnail. PNG has no
/// shrink-on-load, so PNG speed is similar to `resize`.
///
/// Use ``HokusaiImage/resize(width:height:options:)`` when:
/// - You need explicit control over the interpolation kernel.
/// - You need fit modes like ``ResizeFit/contain`` or ``ResizeFit/outside``.
/// - The image is already loaded and you want consistent kernel behaviour.
public struct ThumbnailOptions: Sendable {
    /// Optional height constraint. `nil` means only the width bound applies
    /// and height is calculated to preserve the source aspect ratio.
    ///
    /// Must be set when ``crop`` is not ``ThumbnailCrop/none`` — a crop
    /// strategy needs a fully specified target rectangle.
    public var height: Int?

    /// Cropping strategy when both width and height are specified and the
    /// source aspect ratio does not match. Default is ``ThumbnailCrop/none``
    /// (fit inside, no crop). Any other value requires ``height``.
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
