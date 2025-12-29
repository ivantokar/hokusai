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
        print("[Composite] ===== FUNCTION ENTRY =====")
        fflush(stdout)
        print("[Composite] START")
        fflush(stdout)
        print("[Composite] x=\(x), y=\(y)")
        fflush(stdout)

        // Ensure both images use VipsBackend
        print("[Composite] Ensuring backends...")
        fflush(stdout)

        print("[Composite] Getting base backend...")
        fflush(stdout)
        let baseBackend = try ensureVipsBackend()
        print("[Composite] Base backend obtained")
        fflush(stdout)

        print("[Composite] Getting overlay backend...")
        fflush(stdout)
        let overlayBackend = try overlay.ensureVipsBackend()
        print("[Composite] Overlay backend obtained")
        fflush(stdout)

        print("[Composite] Backends OK")
        fflush(stdout)

        print("[Composite] Getting pointers...")
        fflush(stdout)

        print("[Composite] Getting base pointer...")
        fflush(stdout)
        let basePointer = try baseBackend.getPointer()
        print("[Composite] Base pointer obtained")
        fflush(stdout)

        print("[Composite] Getting overlay pointer...")
        fflush(stdout)
        let overlayPointer = try overlayBackend.getPointer()
        print("[Composite] Overlay pointer obtained")
        fflush(stdout)

        print("[Composite] Pointers OK")
        fflush(stdout)

        print("[Composite] Getting dimensions...")
        fflush(stdout)

        print("[Composite] Getting base width...")
        fflush(stdout)
        let baseWidth = try baseBackend.getWidth()
        print("[Composite] Base width: \(baseWidth)")
        fflush(stdout)

        print("[Composite] Getting base height...")
        fflush(stdout)
        let baseHeight = try baseBackend.getHeight()
        print("[Composite] Base dimensions: \(baseWidth)x\(baseHeight)")
        fflush(stdout)

        // Ensure both images are RGBA (same colorspace and bands)
        print("[Composite] Converting to RGBA...")
        fflush(stdout)

        print("[Composite] Converting base to RGBA...")
        fflush(stdout)
        let baseWithAlpha = try ensureRGBA(basePointer)
        print("[Composite] Base RGBA OK")
        fflush(stdout)

        print("[Composite] Converting overlay to RGBA...")
        fflush(stdout)
        let overlayWithAlpha = try ensureRGBA(overlayPointer)
        print("[Composite] Overlay RGBA OK")
        fflush(stdout)

        // Debug: log image properties
        print("[Composite] Logging image properties...")
        fflush(stdout)

        print("[Composite] Getting base properties...")
        fflush(stdout)
        let baseW = vips_image_get_width(baseWithAlpha)
        let baseH = vips_image_get_height(baseWithAlpha)
        let baseBands = vips_image_get_bands(baseWithAlpha)
        print("[Composite] Base: \(baseW)x\(baseH), bands: \(baseBands)")
        fflush(stdout)

        print("[Composite] Getting overlay properties...")
        fflush(stdout)
        let overlayW = vips_image_get_width(overlayWithAlpha)
        let overlayH = vips_image_get_height(overlayWithAlpha)
        let overlayBands = vips_image_get_bands(overlayWithAlpha)
        print("[Composite] Overlay: \(overlayW)x\(overlayH), bands: \(overlayBands)")
        fflush(stdout)

        print("[Composite] Position: x=\(x), y=\(y)")
        fflush(stdout)

        // Embed overlay on a transparent canvas matching base dimensions
        // (vips_composite requires all images to be the same size)
        print("[Composite] Creating background array...")
        fflush(stdout)
        let background: [Double] = [0, 0, 0, 0]
        let vipsBackground = background.withUnsafeBufferPointer { ptr in
            swift_vips_array_double_new(ptr.baseAddress, Int32(background.count))
        }
        print("[Composite] Background array created")
        fflush(stdout)

        guard let bgArray = vipsBackground else {
            print("[Composite] ERROR: Background array is nil!")
            fflush(stdout)
            throw HokusaiError.vipsError("Failed to create background array")
        }
        print("[Composite] Background array validated")
        fflush(stdout)

        print("[Composite] Calling swift_vips_embed...")
        fflush(stdout)
        var positionedOverlay: UnsafeMutablePointer<CVips.VipsImage>?
        let embedResult = swift_vips_embed(
            overlayWithAlpha,
            &positionedOverlay,
            Int32(x),
            Int32(y),
            Int32(baseWidth),
            Int32(baseHeight),
            bgArray
        )
        print("[Composite] Embed call complete, result=\(embedResult)")
        fflush(stdout)

        print("[Composite] Checking embed result...")
        fflush(stdout)

        guard embedResult == 0, let embedded = positionedOverlay else {
            // Cleanup on embed failure
            print("[Composite] ERROR: Embed failed with result=\(embedResult), positionedOverlay=\(String(describing: positionedOverlay))")
            fflush(stdout)
            g_object_unref(baseWithAlpha)
            g_object_unref(overlayWithAlpha)
            vips_area_unref(UnsafeMutablePointer(mutating: UnsafeRawPointer(bgArray).assumingMemoryBound(to: VipsArea.self)))
            throw HokusaiError.vipsError(VipsBackend.getLastError())
        }

        print("[Composite] Embed succeeded, embedded image pointer: \(String(describing: embedded))")
        fflush(stdout)

        print("[Composite] Getting embedded image dimensions...")
        fflush(stdout)
        let embeddedWidth = vips_image_get_width(embedded)
        print("[Composite] Embedded width: \(embeddedWidth)")
        fflush(stdout)

        let embeddedHeight = vips_image_get_height(embedded)
        print("[Composite] Embedded height: \(embeddedHeight)")
        fflush(stdout)

        let embeddedBands = vips_image_get_bands(embedded)
        print("[Composite] Embedded: \(embeddedWidth)x\(embeddedHeight), bands: \(embeddedBands)")
        fflush(stdout)

        print("[Composite] Calling vips_composite...")
        fflush(stdout)

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
        print("[Composite] About to call swift_vips_composite2 with mode=\(vipsMode)...")
        fflush(stdout)

        var output: UnsafeMutablePointer<CVips.VipsImage>?
        print("[Composite] Calling NOW...")
        fflush(stdout)

        let result = swift_vips_composite2(baseWithAlpha, embedded, &output, vipsMode)

        print("[Composite] swift_vips_composite2 RETURNED, result=\(result)")
        fflush(stdout)

        print("[Composite] vips_composite result=\(result), output=\(String(describing: output))")
        fflush(stdout)

        guard result == 0, let out = output else {
            print("[Composite] ERROR: Composite failed with result=\(result)")
            // Cleanup on error
            g_object_unref(baseWithAlpha)
            g_object_unref(overlayWithAlpha)
            g_object_unref(embedded)
            vips_area_unref(UnsafeMutablePointer(mutating: UnsafeRawPointer(bgArray).assumingMemoryBound(to: VipsArea.self)))
            throw HokusaiError.vipsError(VipsBackend.getLastError())
        }

        // Cleanup: unreference intermediate images that are no longer needed
        g_object_unref(baseWithAlpha)
        g_object_unref(overlayWithAlpha)
        g_object_unref(embedded)
        vips_area_unref(UnsafeMutablePointer(mutating: UnsafeRawPointer(bgArray).assumingMemoryBound(to: VipsArea.self)))

        return HokusaiImage(backend: .vips(VipsBackend(takingOwnership: out)))
    }

    // MARK: - Private Helpers

    /// Ensure image is RGBA (4 bands: RGB with alpha)
    /// Converts grayscale to RGB if needed, then adds alpha channel if needed
    private func ensureRGBA(_ image: UnsafeMutablePointer<CVips.VipsImage>) throws -> UnsafeMutablePointer<CVips.VipsImage> {
        print("[ensureRGBA] START")
        fflush(stdout)

        print("[ensureRGBA] Getting bands...")
        fflush(stdout)
        let bands = vips_image_get_bands(image)
        print("[ensureRGBA] Input bands: \(bands)")
        fflush(stdout)

        // If already RGBA (4 bands), return a copy
        if bands == 4 {
            print("[ensureRGBA] Already 4 bands, copying...")
            fflush(stdout)
            var output: UnsafeMutablePointer<CVips.VipsImage>?
            let result = swift_vips_copy(image, &output)
            guard result == 0, let out = output else {
                print("[ensureRGBA] ERROR: Copy failed")
                fflush(stdout)
                throw HokusaiError.vipsError(VipsBackend.getLastError())
            }
            print("[ensureRGBA] Already RGBA, returning copy")
            fflush(stdout)
            return out
        }

        // If grayscale (1 or 2 bands), convert to RGB
        // vips_colourspace preserves alpha channel automatically
        var rgbImage = image
        if bands == 1 || bands == 2 {
            print("[ensureRGBA] Converting grayscale to RGB...")
            var converted: UnsafeMutablePointer<CVips.VipsImage>?

            // Convert to sRGB colorspace (preserves alpha if present)
            let convertResult = swift_vips_colourspace(image, &converted, VIPS_INTERPRETATION_sRGB)

            guard convertResult == 0, let conv = converted else {
                throw HokusaiError.vipsError(VipsBackend.getLastError())
            }

            rgbImage = conv
            print("[ensureRGBA] Converted to RGB, now bands: \(vips_image_get_bands(rgbImage))")
        }

        // Now add alpha channel if not already present
        let currentBands = vips_image_get_bands(rgbImage)
        if currentBands == 3 {
            print("[ensureRGBA] Adding alpha channel (3 bands -> 4 bands)...")
            var output: UnsafeMutablePointer<CVips.VipsImage>?
            let result = swift_vips_addalpha(rgbImage, &output)

            guard result == 0, let out = output else {
                // Clean up on error
                if rgbImage != image {
                    g_object_unref(rgbImage)
                }
                throw HokusaiError.vipsError(VipsBackend.getLastError())
            }

            // Success: clean up intermediate RGB image
            if rgbImage != image {
                g_object_unref(rgbImage)
            }

            print("[ensureRGBA] Final bands: \(vips_image_get_bands(out))")
            return out
        }

        // Already 4 bands after colorspace conversion
        print("[ensureRGBA] Final bands: \(vips_image_get_bands(rgbImage))")
        return rgbImage
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
