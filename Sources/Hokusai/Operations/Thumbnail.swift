import Foundation
import CVips

extension HokusaiImage {
    /// Resize using libvips thumbnail logic on an already-loaded image.
    ///
    /// This calls `vips_thumbnail_image()` internally. Unlike
    /// ``Hokusai/thumbnail(from:width:options:)``, there is no shrink-on-load
    /// benefit because the source is already fully decoded in memory. The
    /// advantage over ``resize(width:height:options:)`` is that libvips
    /// selects the convolution kernel automatically based on the shrink ratio
    /// and applies EXIF auto-rotation by default.
    ///
    /// Prefer ``Hokusai/thumbnail(from:width:options:)`` when the source is a
    /// file path or raw buffer and you want the full shrink-on-load speedup.
    ///
    /// - Parameters:
    ///   - width: Target width (1...Int32.max). Height is constrained by
    ///     `options.height`; if `nil` the aspect ratio is preserved.
    ///   - options: Cropping strategy and rotation behaviour. Crop strategies
    ///     other than ``ThumbnailCrop/none`` require `options.height`.
    /// - Returns: A new ``HokusaiImage`` at the requested dimensions.
    /// - Throws: ``HokusaiError/invalidOption(name:reason:)`` for invalid
    ///   dimensions, or ``HokusaiError/transform(_:)`` when the libvips
    ///   thumbnail transformation fails.
    public func thumbnail(width: Int, options: ThumbnailOptions = ThumbnailOptions()) throws -> HokusaiImage {
        HokusaiImage(native: try native().thumbnail(width: width, options: options))
    }
}

extension NativeImage {
    /// Resizes with `vips_thumbnail_image()` on an already-opened image.
    func thumbnail(width: Int, options: ThumbnailOptions) throws -> NativeImage {
        let arguments = try ThumbnailArguments.validate(width: width, options: options)
        return try applying("thumbnail") { input, output in
            swift_vips_thumbnail_image(
                input, output, arguments.width, arguments.height, arguments.crop, arguments.noRotate)
        }
    }
}
