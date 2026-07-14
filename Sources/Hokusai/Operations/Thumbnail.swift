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
    /// - Throws: ``HokusaiError/invalidDimensions(_:)`` for invalid
    ///   dimensions, or ``HokusaiError/vipsError(_:)`` when the libvips
    ///   thumbnail transformation fails.
    public func thumbnail(width: Int, options: ThumbnailOptions = ThumbnailOptions()) throws -> HokusaiImage {
        let arguments = try ThumbnailArguments.validate(width: width, options: options)
        let backend = try ensureVipsBackend()
        let pointer = try backend.getPointer()

        var output: UnsafeMutablePointer<CVips.VipsImage>?
        let result = swift_vips_thumbnail_image(
            pointer, &output, arguments.width, arguments.height, arguments.crop, arguments.noRotate)

        guard result == 0, let out = output else {
            throw HokusaiError.vipsError("thumbnail transformation failed: \(VipsBackend.getLastError())")
        }

        return HokusaiImage(backend: .vips(VipsBackend(takingOwnership: out)))
    }
}
