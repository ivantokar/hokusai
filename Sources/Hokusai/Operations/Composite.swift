import Foundation
import CVips

/// The blend modes currently supported by Hokusai compositing.
public enum BlendMode: Sendable {
    /// Standard Porter-Duff source-over compositing.
    case over
    /// Adds colour components, producing a lighter result.
    case add
    /// Multiplies colour components, producing a darker result.
    case multiply
}

/// Options for a legacy image-overlay operation.
public struct CompositeOptions: Sendable {
    /// The rule used to combine base and overlay pixels.
    public var mode: BlendMode

    /// Overlay opacity clamped to the range `0...1` during initialization.
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
    /// Draws `overlay` over this image at the supplied pixel offset.
    ///
    /// Example:
    /// ```swift
    /// let watermarked = try baseImage.composite(
    /// overlay: logoImage,
    /// x: 10,
    /// y: 10,
    /// options: CompositeOptions(mode: .over, opacity: 0.8)
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

        // Normalize both sources before blending so alpha handling does not
        // depend on whether an input started as grayscale, RGB, or RGBA.
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
            VipsBackend.discardPartialImage(output)
            throw HokusaiError.vipsError(VipsBackend.getLastError())
        }

        return HokusaiImage(backend: .vips(VipsBackend(takingOwnership: out)))
    }

    // MARK: - Private Helpers

    /// Multiplies the alpha band while preserving the RGB bands unchanged.
    private func applyOpacity(
        _ image: UnsafeMutablePointer<CVips.VipsImage>,
        opacity: Double
    ) throws -> UnsafeMutablePointer<CVips.VipsImage> {
        guard opacity < 1.0 else { return image }

        var rgbImage: UnsafeMutablePointer<CVips.VipsImage>?
        let rgbResult = swift_vips_extract_band(image, &rgbImage, 0, 3)
        guard rgbResult == 0, let rgb = rgbImage else {
            VipsBackend.discardPartialImage(rgbImage)
            throw HokusaiError.vipsError(VipsBackend.getLastError())
        }

        var alphaImage: UnsafeMutablePointer<CVips.VipsImage>?
        let alphaResult = swift_vips_extract_band(image, &alphaImage, 3, 1)
        guard alphaResult == 0, let alpha = alphaImage else {
            g_object_unref(rgb)
            VipsBackend.discardPartialImage(alphaImage)
            throw HokusaiError.vipsError(VipsBackend.getLastError())
        }

        var scaledAlphaImage: UnsafeMutablePointer<CVips.VipsImage>?
        let scaleResult = swift_vips_linear1(alpha, &scaledAlphaImage, opacity, 0)
        guard scaleResult == 0, let scaledAlpha = scaledAlphaImage else {
            g_object_unref(rgb)
            g_object_unref(alpha)
            VipsBackend.discardPartialImage(scaledAlphaImage)
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
            VipsBackend.discardPartialImage(output)
            throw HokusaiError.vipsError(VipsBackend.getLastError())
        }

        return out
    }

    /// Returns an owned RGBA copy suitable for native compositing.
    private func ensureRGBA(_ image: UnsafeMutablePointer<CVips.VipsImage>) throws -> UnsafeMutablePointer<CVips.VipsImage> {
        let bands = vips_image_get_bands(image)

        // A copy gives this helper a consistently owned result to return.
        if bands == 4 {
            var output: UnsafeMutablePointer<CVips.VipsImage>?
            let result = swift_vips_copy(image, &output)
            guard result == 0, let out = output else {
                VipsBackend.discardPartialImage(output)
                throw HokusaiError.vipsError(VipsBackend.getLastError())
            }
            return out
        }

        // Expand grayscale input before adding alpha so channels have RGB meaning.
        var rgbImage = image
        if bands == 1 || bands == 2 {
            var converted: UnsafeMutablePointer<CVips.VipsImage>?
            let convertResult = swift_vips_colourspace(image, &converted, VIPS_INTERPRETATION_sRGB)
            guard convertResult == 0, let conv = converted else {
                VipsBackend.discardPartialImage(converted)
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
                VipsBackend.discardPartialImage(output)
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
