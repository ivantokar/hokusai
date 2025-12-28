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
        // Ensure both images use VipsBackend
        let baseBackend = try ensureVipsBackend()
        let overlayBackend = try overlay.ensureVipsBackend()

        let basePointer = try baseBackend.getPointer()
        var overlayPointer = try overlayBackend.getPointer()

        let baseWidth = try baseBackend.getWidth()
        let baseHeight = try baseBackend.getHeight()
        let overlayWidth = try overlayBackend.getWidth()
        let overlayHeight = try overlayBackend.getHeight()

        // Apply opacity if needed
        if options.opacity < 1.0 {
            overlayPointer = try applyOpacity(to: overlayPointer, opacity: options.opacity)
        }

        // If overlay needs to be positioned, embed it on a transparent canvas
        var positionedOverlay = overlayPointer
        if x != 0 || y != 0 {
            positionedOverlay = try embedOverlay(
                overlayPointer,
                x: x,
                y: y,
                baseWidth: baseWidth,
                baseHeight: baseHeight,
                overlayWidth: overlayWidth,
                overlayHeight: overlayHeight
            )
        }

        // Ensure both images have alpha channel
        let baseWithAlpha = try ensureAlpha(basePointer)
        let overlayWithAlpha = try ensureAlpha(positionedOverlay)

        // Map blend mode to VipsBlendMode
        let vipsMode: VipsBlendMode
        switch options.mode {
        case .over:
            vipsMode = VIPS_BLEND_MODE_OVER
        case .add:
            vipsMode = VIPS_BLEND_MODE_ADD
        case .multiply:
            vipsMode = VIPS_BLEND_MODE_MULTIPLY
        }

        // Perform composite
        var output: UnsafeMutablePointer<CVips.VipsImage>?
        let result = swift_vips_composite2(baseWithAlpha, overlayWithAlpha, &output, vipsMode)

        guard result == 0, let out = output else {
            throw HokusaiError.vipsError(VipsBackend.getLastError())
        }

        return HokusaiImage(backend: .vips(VipsBackend(takingOwnership: out)))
    }

    // MARK: - Private Helpers

    /// Apply opacity to an image by multiplying the alpha channel
    private func applyOpacity(to image: UnsafeMutablePointer<CVips.VipsImage>, opacity: Double) throws -> UnsafeMutablePointer<CVips.VipsImage> {
        // Ensure image has alpha
        let withAlpha = try ensureAlpha(image)

        // Multiply alpha channel by opacity
        var output: UnsafeMutablePointer<CVips.VipsImage>?
        let result = swift_vips_linear1(withAlpha, &output, opacity, 0.0)

        guard result == 0, let out = output else {
            throw HokusaiError.vipsError(VipsBackend.getLastError())
        }

        return out
    }

    /// Embed overlay image on a transparent canvas matching base dimensions
    private func embedOverlay(
        _ overlay: UnsafeMutablePointer<CVips.VipsImage>,
        x: Int,
        y: Int,
        baseWidth: Int,
        baseHeight: Int,
        overlayWidth: Int,
        overlayHeight: Int
    ) throws -> UnsafeMutablePointer<CVips.VipsImage> {
        // Create transparent background (RGBA: 0, 0, 0, 0)
        let background: [Double] = [0, 0, 0, 0]
        let backgroundArray = background.withUnsafeBufferPointer { ptr in
            swift_vips_array_double_new(ptr.baseAddress, Int32(background.count))
        }

        var output: UnsafeMutablePointer<CVips.VipsImage>?
        let result = swift_vips_embed(
            overlay,
            &output,
            Int32(x),
            Int32(y),
            Int32(baseWidth),
            Int32(baseHeight),
            backgroundArray
        )

        guard result == 0, let out = output else {
            throw HokusaiError.vipsError(VipsBackend.getLastError())
        }

        return out
    }

    /// Ensure image has alpha channel
    private func ensureAlpha(_ image: UnsafeMutablePointer<CVips.VipsImage>) throws -> UnsafeMutablePointer<CVips.VipsImage> {
        let bands = vips_image_get_bands(image)

        // If already has alpha (4 bands for RGB, 2 for grayscale), return as-is
        if bands == 4 || bands == 2 {
            // Need to copy to avoid modifying original
            var output: UnsafeMutablePointer<CVips.VipsImage>?
            let result = swift_vips_copy(image, &output)
            guard result == 0, let out = output else {
                throw HokusaiError.vipsError(VipsBackend.getLastError())
            }
            return out
        }

        // Add alpha channel
        var output: UnsafeMutablePointer<CVips.VipsImage>?
        let result = swift_vips_addalpha(image, &output)

        guard result == 0, let out = output else {
            throw HokusaiError.vipsError(VipsBackend.getLastError())
        }

        return out
    }
}
