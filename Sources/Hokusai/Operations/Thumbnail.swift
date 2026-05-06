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
    ///   - width: Target width. Height is constrained by `options.height`; if
    ///     `nil` the aspect ratio is preserved.
    ///   - options: Cropping strategy and rotation behaviour.
    /// - Returns: A new ``HokusaiImage`` at the requested dimensions.
    public func thumbnail(width: Int, options: ThumbnailOptions = ThumbnailOptions()) throws -> HokusaiImage {
        let backend = try ensureVipsBackend()
        let pointer = try backend.getPointer()

        let height = Int32(options.height ?? 0)
        let crop = mapThumbnailCrop(options.crop)
        let noRotate = Int32(options.noRotate ? 1 : 0)

        var output: UnsafeMutablePointer<CVips.VipsImage>?
        let result = swift_vips_thumbnail_image(pointer, &output, Int32(width), height, crop, noRotate)

        guard result == 0, let out = output else {
            throw HokusaiError.vipsError(VipsBackend.getLastError())
        }

        return HokusaiImage(backend: .vips(VipsBackend(takingOwnership: out)))
    }

    // MARK: - Private

    private func mapThumbnailCrop(_ crop: ThumbnailCrop) -> VipsInteresting {
        switch crop {
        case .none:      return VIPS_INTERESTING_NONE
        case .centre:    return VIPS_INTERESTING_CENTRE
        case .attention: return VIPS_INTERESTING_ATTENTION
        case .entropy:   return VIPS_INTERESTING_ENTROPY
        }
    }
}
