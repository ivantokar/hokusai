import Foundation
import CVips

/// Blend modes for image compositing
public enum BlendMode: Sendable {
    /// Porter-Duff over (default alpha compositing)
    case over
    /// Add (lighten)
    case add
    /// Multiply (darken)
    case multiply
}

/// Options for image compositing
public struct CompositeOptions: Sendable {
    /// Blend mode
    public var mode: BlendMode

    /// Opacity of overlay image (0.0 - 1.0)
    public var opacity: Double

    public init(
        mode: BlendMode = .over,
        opacity: Double = 1.0
    ) {
        self.mode = mode
        self.opacity = min(max(opacity, 0.0), 1.0)
    }
}

extension HokusaiImage {
    /// Composite (overlay) another image on top of this image
    ///
    /// This operation places the overlay image at the specified position with optional opacity and blend mode.
    ///
    /// Example:
    /// ```swift
    /// let watermarked = try baseImage.composite(
    ///     overlay: logoImage,
    ///     x: 10,
    ///     y: 10,
    ///     options: CompositeOptions(mode: .over, opacity: 0.8)
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - overlay: The image to overlay on top
    ///   - x: Horizontal position (left edge of overlay)
    ///   - y: Vertical position (top edge of overlay)
    ///   - options: Composite options (blend mode, opacity)
    /// - Returns: New image with overlay composited
    public func composite(
        overlay: HokusaiImage,
        x: Int = 0,
        y: Int = 0,
        options: CompositeOptions = CompositeOptions()
    ) throws -> HokusaiImage {
        let baseBackend = try ensureVipsBackend()
        let overlayBackend = try overlay.ensureVipsBackend()

        let basePointer = try baseBackend.getPointer()
        let overlayPointer = try overlayBackend.getPointer()

        // Normalize inputs to RGBA so compositing behaves consistently.
        let baseWithAlpha = try ensureRGBA(basePointer)
        defer { g_object_unref(baseWithAlpha) }

        let overlayWithAlpha = try ensureRGBA(overlayPointer)
        var overlayForComposite = overlayWithAlpha
        if options.opacity < 1.0 {
            overlayForComposite = try applyOpacity(overlayWithAlpha, opacity: options.opacity)
            if overlayForComposite != overlayWithAlpha {
                g_object_unref(overlayWithAlpha)
            }
        }
        defer { g_object_unref(overlayForComposite) }

        let vipsMode: VipsBlendMode
        switch options.mode {
        case .over:
            vipsMode = VIPS_BLEND_MODE_OVER
        case .add:
            vipsMode = VIPS_BLEND_MODE_ADD
        case .multiply:
            vipsMode = VIPS_BLEND_MODE_MULTIPLY
        }

        var output: UnsafeMutablePointer<CVips.VipsImage>?
        let result = swift_vips_composite2(
            baseWithAlpha,
            overlayForComposite,
            &output,
            vipsMode,
            Int32(x),
            Int32(y)
        )

        guard result == 0, let out = output else {
            throw HokusaiError.vipsError(VipsBackend.getLastError())
        }

        return HokusaiImage(backend: .vips(VipsBackend(takingOwnership: out)))
    }

    // MARK: - Private Helpers

    private func applyOpacity(
        _ image: UnsafeMutablePointer<CVips.VipsImage>,
        opacity: Double
    ) throws -> UnsafeMutablePointer<CVips.VipsImage> {
        guard opacity < 1.0 else { return image }

        var rgbImage: UnsafeMutablePointer<CVips.VipsImage>?
        let rgbResult = swift_vips_extract_band(image, &rgbImage, 0, 3)
        guard rgbResult == 0, let rgb = rgbImage else {
            throw HokusaiError.vipsError(VipsBackend.getLastError())
        }

        var alphaImage: UnsafeMutablePointer<CVips.VipsImage>?
        let alphaResult = swift_vips_extract_band(image, &alphaImage, 3, 1)
        guard alphaResult == 0, let alpha = alphaImage else {
            g_object_unref(rgb)
            throw HokusaiError.vipsError(VipsBackend.getLastError())
        }

        var scaledAlphaImage: UnsafeMutablePointer<CVips.VipsImage>?
        let scaleResult = swift_vips_linear1(alpha, &scaledAlphaImage, opacity, 0)
        guard scaleResult == 0, let scaledAlpha = scaledAlphaImage else {
            g_object_unref(rgb)
            g_object_unref(alpha)
            throw HokusaiError.vipsError(VipsBackend.getLastError())
        }

        var output: UnsafeMutablePointer<CVips.VipsImage>?
        var inputs: [UnsafeMutablePointer<CVips.VipsImage>?] = [rgb, scaledAlpha]
        let joinResult = inputs.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let baseAddress = buffer.baseAddress else {
                return -1
            }
            return swift_vips_bandjoin(baseAddress, &output, Int32(buffer.count))
        }

        g_object_unref(rgb)
        g_object_unref(alpha)
        g_object_unref(scaledAlpha)

        guard joinResult == 0, let out = output else {
            throw HokusaiError.vipsError(VipsBackend.getLastError())
        }

        return out
    }

    /// Ensure image is RGBA (4 bands: RGB with alpha)
    /// Converts grayscale to RGB if needed, then adds alpha channel if needed
    private func ensureRGBA(_ image: UnsafeMutablePointer<CVips.VipsImage>) throws -> UnsafeMutablePointer<CVips.VipsImage> {
        let bands = vips_image_get_bands(image)

        // If already RGBA (4 bands), return a copy.
        if bands == 4 {
            var output: UnsafeMutablePointer<CVips.VipsImage>?
            let result = swift_vips_copy(image, &output)
            guard result == 0, let out = output else {
                throw HokusaiError.vipsError(VipsBackend.getLastError())
            }
            return out
        }

        // If grayscale (1 or 2 bands), convert to RGB.
        var rgbImage = image
        if bands == 1 || bands == 2 {
            var converted: UnsafeMutablePointer<CVips.VipsImage>?
            let convertResult = swift_vips_colourspace(image, &converted, VIPS_INTERPRETATION_sRGB)
            guard convertResult == 0, let conv = converted else {
                throw HokusaiError.vipsError(VipsBackend.getLastError())
            }
            rgbImage = conv
        }

        let currentBands = vips_image_get_bands(rgbImage)
        if currentBands == 3 {
            var output: UnsafeMutablePointer<CVips.VipsImage>?
            let result = swift_vips_addalpha(rgbImage, &output)

            guard result == 0, let out = output else {
                if rgbImage != image {
                    g_object_unref(rgbImage)
                }
                throw HokusaiError.vipsError(VipsBackend.getLastError())
            }

            if rgbImage != image {
                g_object_unref(rgbImage)
            }

            return out
        }

        return rgbImage
    }
}
