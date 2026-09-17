import Foundation
import CVips

extension HokusaiImage {
    /// Returns a resized legacy image handle using libvips.
    ///
    /// The method first computes a proportional intermediate size. `cover`
    /// crops that result, while `contain` embeds it in the requested canvas.
    /// This mirrors the geometry rules used by the 1.0 pipeline API.
    public func resize(width: Int? = nil, height: Int? = nil, options: ResizeOptions = ResizeOptions()) throws -> HokusaiImage {
        let vipsBackend = try ensureVipsBackend()
        let pointer = try vipsBackend.getPointer()

        let currentWidth = try vipsBackend.getWidth()
        let currentHeight = try vipsBackend.getHeight()

        // Explicit arguments take precedence over dimensions stored in options.
        let targetWidth = width ?? options.width
        let targetHeight = height ?? options.height

        guard targetWidth != nil || targetHeight != nil else {
            throw HokusaiError.invalidOperation("Must specify at least width or height")
        }

        // Resolve the proportional intermediate image before crop or padding.
        let (finalWidth, finalHeight) = try calculateDimensions(
            currentWidth: currentWidth,
            currentHeight: currentHeight,
            targetWidth: targetWidth,
            targetHeight: targetHeight,
            fit: options.fit,
            withoutEnlargement: options.withoutEnlargement,
            withoutReduction: options.withoutReduction
        )

        // libvips resize accepts horizontal and vertical scale factors.
        let hscale = Double(finalWidth) / Double(currentWidth)
        let vscale = Double(finalHeight) / Double(currentHeight)

        var output: UnsafeMutablePointer<CVips.VipsImage>?

        // Keep Swift's stable kernel names separate from native enum values.
        let vipsKernel = mapKernel(options.kernel)

        // The native call returns a new owned image; the input remains valid.
        let result = swift_vips_resize(pointer, &output, hscale, vscale, vipsKernel)

        guard result == 0, let out = output else {
            VipsBackend.discardPartialImage(output)
            throw HokusaiError.vipsError(VipsBackend.getLastError())
        }

        let resized = HokusaiImage(backend: .vips(VipsBackend(takingOwnership: out)))

        // Cover and contain need a second step after proportional resampling.
        switch options.fit {
        case .cover:
            if let w = targetWidth, let h = targetHeight {
                return try resized.smartCrop(width: w, height: h, position: options.position)
            }
            return resized

        case .contain:
            if let w = targetWidth, let h = targetHeight {
                let background = options.background ?? [0, 0, 0, 255]
                return try resized.embed(
                    width: w,
                    height: h,
                    position: options.position,
                    background: background
                )
            }
            return resized

        default:
            return resized
        }
    }

    /// Stretches the image to exact dimensions without preserving aspect ratio.
    public func resize(width: Int, height: Int) throws -> HokusaiImage {
        var options = ResizeOptions()
        options.fit = .fill
        return try resize(width: width, height: height, options: options)
    }

    /// Resizes to fit inside optional bounds without cropping.
    public func resizeToFit(width: Int? = nil, height: Int? = nil) throws -> HokusaiImage {
        var options = ResizeOptions()
        options.fit = .inside
        return try resize(width: width, height: height, options: options)
    }

    /// Resizes to cover bounds and crops overflow at the selected position.
    public func resizeToCover(width: Int, height: Int, position: Position = .center) throws -> HokusaiImage {
        var options = ResizeOptions()
        options.fit = .cover
        options.position = position
        return try resize(width: width, height: height, options: options)
    }

    // MARK: - Private Helpers

    /// Calculates the proportional intermediate size before crop or canvas padding.
    private func calculateDimensions(
        currentWidth: Int,
        currentHeight: Int,
        targetWidth: Int?,
        targetHeight: Int?,
        fit: ResizeFit,
        withoutEnlargement: Bool,
        withoutReduction: Bool
    ) throws -> (width: Int, height: Int) {
        // Calculate geometry in Swift so all native calls receive one coherent,
        // positive target size. Size constraints are applied after fit math.
        let aspectRatio = Double(currentWidth) / Double(currentHeight)

        var finalWidth: Int
        var finalHeight: Int

        switch fit {
        case .fill:
            finalWidth = targetWidth ?? currentWidth
            finalHeight = targetHeight ?? currentHeight

        case .inside, .contain:
            if let w = targetWidth, let h = targetHeight {
                // Choose the largest proportional size that remains inside both bounds.
                let targetAspect = Double(w) / Double(h)
                if aspectRatio > targetAspect {
                    finalWidth = w
                    finalHeight = Int(Double(w) / aspectRatio)
                } else {
                    finalHeight = h
                    finalWidth = Int(Double(h) * aspectRatio)
                }
            } else if let w = targetWidth {
                // Preserve aspect ratio when width is the only constraint.
                finalWidth = w
                finalHeight = Int(Double(w) / aspectRatio)
            } else if let h = targetHeight {
                // Preserve aspect ratio when height is the only constraint.
                finalHeight = h
                finalWidth = Int(Double(h) * aspectRatio)
            } else {
                throw HokusaiError.invalidOperation("Must specify at least one dimension")
            }

        case .outside, .cover:
            if let w = targetWidth, let h = targetHeight {
                // Choose the smallest proportional size that covers both bounds.
                let targetAspect = Double(w) / Double(h)
                if aspectRatio > targetAspect {
                    finalHeight = h
                    finalWidth = Int(Double(h) * aspectRatio)
                } else {
                    finalWidth = w
                    finalHeight = Int(Double(w) / aspectRatio)
                }
            } else if let w = targetWidth {
                // A single width still preserves aspect ratio for cover/outside.
                finalWidth = w
                finalHeight = Int(Double(w) / aspectRatio)
            } else if let h = targetHeight {
                // A single height still preserves aspect ratio for cover/outside.
                finalHeight = h
                finalWidth = Int(Double(h) * aspectRatio)
            } else {
                throw HokusaiError.invalidOperation("Must specify at least one dimension")
            }
        }

        // Clamp the calculated result when callers forbid upscaling or downscaling.
        if withoutEnlargement {
            if finalWidth > currentWidth || finalHeight > currentHeight {
                finalWidth = currentWidth
                finalHeight = currentHeight
            }
        }

        if withoutReduction {
            if finalWidth < currentWidth || finalHeight < currentHeight {
                finalWidth = currentWidth
                finalHeight = currentHeight
            }
        }

        return (finalWidth, finalHeight)
    }

    /// Maps the stable legacy kernel names to the libvips convolution enum.
    private func mapKernel(_ kernel: Kernel) -> VipsKernel {
        switch kernel {
        case .nearest: return VIPS_KERNEL_NEAREST
        case .linear: return VIPS_KERNEL_LINEAR
        case .cubic: return VIPS_KERNEL_CUBIC
        case .mitchell: return VIPS_KERNEL_MITCHELL
        case .lanczos2: return VIPS_KERNEL_LANCZOS2
        case .lanczos3: return VIPS_KERNEL_LANCZOS3
        }
    }

    /// Places the resized image on a larger canvas using an owned RGBA background.
    private func embed(width: Int, height: Int, position: Position, background: [Double]) throws -> HokusaiImage {
        let vipsBackend = try ensureVipsBackend()
        let pointer = try vipsBackend.getPointer()
        let currentWidth = try vipsBackend.getWidth()
        let currentHeight = try vipsBackend.getHeight()

        // Compute the top-left origin for the requested canvas anchor.
        let (x, y) = calculateEmbedPosition(
            imageWidth: currentWidth,
            imageHeight: currentHeight,
            targetWidth: width,
            targetHeight: height,
            position: position
        )

        var output: UnsafeMutablePointer<CVips.VipsImage>?

        // libvips expects an owned VipsArray for the RGBA background.
        let vipsBackground = background.withUnsafeBufferPointer { ptr in
            swift_vips_array_double_new(ptr.baseAddress, Int32(background.count))
        }

        guard let bgArray = vipsBackground else {
            throw HokusaiError.vipsError("Failed to create background array")
        }

        let result = swift_vips_embed(pointer, &output, Int32(x), Int32(y), Int32(width), Int32(height), bgArray)

        guard result == 0, let out = output else {
            VipsBackend.discardPartialImage(output)
            vips_area_unref(UnsafeMutablePointer(mutating: UnsafeRawPointer(bgArray).assumingMemoryBound(to: VipsArea.self)))
            throw HokusaiError.vipsError(VipsBackend.getLastError())
        }

        vips_area_unref(UnsafeMutablePointer(mutating: UnsafeRawPointer(bgArray).assumingMemoryBound(to: VipsArea.self)))

        return HokusaiImage(backend: .vips(VipsBackend(takingOwnership: out)))
    }

    /// Resolves a canvas anchor into the top-left position for the resized image.
    private func calculateEmbedPosition(
        imageWidth: Int,
        imageHeight: Int,
        targetWidth: Int,
        targetHeight: Int,
        position: Position
    ) -> (x: Int, y: Int) {
        let xOffset = (targetWidth - imageWidth) / 2
        let yOffset = (targetHeight - imageHeight) / 2

        switch position {
        case .center:
            return (xOffset, yOffset)
        case .top:
            return (xOffset, 0)
        case .bottom:
            return (xOffset, targetHeight - imageHeight)
        case .left:
            return (0, yOffset)
        case .right:
            return (targetWidth - imageWidth, yOffset)
        case .topLeft:
            return (0, 0)
        case .topRight:
            return (targetWidth - imageWidth, 0)
        case .bottomLeft:
            return (0, targetHeight - imageHeight)
        case .bottomRight:
            return (targetWidth - imageWidth, targetHeight - imageHeight)
        default:
            return (xOffset, yOffset)
        }
    }
}
