import Foundation
import CVips

extension HokusaiImage {
    /// Resize image with various fit modes
    public func resize(width: Int? = nil, height: Int? = nil, options: ResizeOptions = ResizeOptions()) throws -> HokusaiImage {
        let vipsBackend = try ensureVipsBackend()
        let pointer = try vipsBackend.getPointer()

        let currentWidth = try vipsBackend.getWidth()
        let currentHeight = try vipsBackend.getHeight()

        // Merge provided dimensions with options
        let targetWidth = width ?? options.width
        let targetHeight = height ?? options.height

        guard targetWidth != nil || targetHeight != nil else {
            throw HokusaiError.invalidOperation("Must specify at least width or height")
        }

        // Calculate target dimensions based on fit mode
        let (finalWidth, finalHeight) = try calculateDimensions(
            currentWidth: currentWidth,
            currentHeight: currentHeight,
            targetWidth: targetWidth,
            targetHeight: targetHeight,
            fit: options.fit,
            withoutEnlargement: options.withoutEnlargement,
            withoutReduction: options.withoutReduction
        )

        // Calculate scale factors
        let hscale = Double(finalWidth) / Double(currentWidth)
        let vscale = Double(finalHeight) / Double(currentHeight)

        var output: UnsafeMutablePointer<CVips.VipsImage>?

        // Map kernel to vips kernel
        let vipsKernel = mapKernel(options.kernel)

        // Perform resize
        let result = swift_vips_resize(pointer, &output, hscale, vscale, vipsKernel)

        guard result == 0, let out = output else {
            throw HokusaiError.vipsError(VipsBackend.getLastError())
        }

        let resized = HokusaiImage(backend: .vips(VipsBackend(takingOwnership: out)))

        // Handle fit modes that require cropping or embedding
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

    /// Resize to exact dimensions (ignoring aspect ratio)
    public func resize(width: Int, height: Int) throws -> HokusaiImage {
        var options = ResizeOptions()
        options.fit = .fill
        return try resize(width: width, height: height, options: options)
    }

    /// Resize to fit within dimensions (preserving aspect ratio)
    public func resizeToFit(width: Int? = nil, height: Int? = nil) throws -> HokusaiImage {
        var options = ResizeOptions()
        options.fit = .inside
        return try resize(width: width, height: height, options: options)
    }

    /// Resize and crop to cover dimensions (preserving aspect ratio)
    public func resizeToCover(width: Int, height: Int, position: Position = .center) throws -> HokusaiImage {
        var options = ResizeOptions()
        options.fit = .cover
        options.position = position
        return try resize(width: width, height: height, options: options)
    }

    // MARK: - Private Helpers

    private func calculateDimensions(
        currentWidth: Int,
        currentHeight: Int,
        targetWidth: Int?,
        targetHeight: Int?,
        fit: ResizeFit,
        withoutEnlargement: Bool,
        withoutReduction: Bool
    ) throws -> (width: Int, height: Int) {
        let aspectRatio = Double(currentWidth) / Double(currentHeight)

        var finalWidth: Int
        var finalHeight: Int

        switch fit {
        case .fill:
            finalWidth = targetWidth ?? currentWidth
            finalHeight = targetHeight ?? currentHeight

        case .inside, .contain:
            if let w = targetWidth, let h = targetHeight {
                // Both dimensions specified
                let targetAspect = Double(w) / Double(h)
                if aspectRatio > targetAspect {
                    finalWidth = w
                    finalHeight = Int(Double(w) / aspectRatio)
                } else {
                    finalHeight = h
                    finalWidth = Int(Double(h) * aspectRatio)
                }
            } else if let w = targetWidth {
                // Only width specified
                finalWidth = w
                finalHeight = Int(Double(w) / aspectRatio)
            } else if let h = targetHeight {
                // Only height specified
                finalHeight = h
                finalWidth = Int(Double(h) * aspectRatio)
            } else {
                throw HokusaiError.invalidOperation("Must specify at least one dimension")
            }

        case .outside, .cover:
            if let w = targetWidth, let h = targetHeight {
                // Both dimensions specified
                let targetAspect = Double(w) / Double(h)
                if aspectRatio > targetAspect {
                    finalHeight = h
                    finalWidth = Int(Double(h) * aspectRatio)
                } else {
                    finalWidth = w
                    finalHeight = Int(Double(w) / aspectRatio)
                }
            } else if let w = targetWidth {
                // Only width specified
                finalWidth = w
                finalHeight = Int(Double(w) / aspectRatio)
            } else if let h = targetHeight {
                // Only height specified
                finalHeight = h
                finalWidth = Int(Double(h) * aspectRatio)
            } else {
                throw HokusaiError.invalidOperation("Must specify at least one dimension")
            }
        }

        // Apply enlargement/reduction constraints
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

    private func embed(width: Int, height: Int, position: Position, background: [Double]) throws -> HokusaiImage {
        let vipsBackend = try ensureVipsBackend()
        let pointer = try vipsBackend.getPointer()
        let currentWidth = try vipsBackend.getWidth()
        let currentHeight = try vipsBackend.getHeight()

        // Calculate position
        let (x, y) = calculateEmbedPosition(
            imageWidth: currentWidth,
            imageHeight: currentHeight,
            targetWidth: width,
            targetHeight: height,
            position: position
        )

        var output: UnsafeMutablePointer<CVips.VipsImage>?

        // Create background array for vips
        let vipsBackground = background.withUnsafeBufferPointer { ptr in
            swift_vips_array_double_new(ptr.baseAddress, Int32(background.count))
        }

        guard let bgArray = vipsBackground else {
            throw HokusaiError.vipsError("Failed to create background array")
        }

        let result = swift_vips_embed(pointer, &output, Int32(x), Int32(y), Int32(width), Int32(height), bgArray)

        guard result == 0, let out = output else {
            vips_area_unref(UnsafeMutablePointer(mutating: UnsafeRawPointer(bgArray).assumingMemoryBound(to: VipsArea.self)))
            throw HokusaiError.vipsError(VipsBackend.getLastError())
        }

        vips_area_unref(UnsafeMutablePointer(mutating: UnsafeRawPointer(bgArray).assumingMemoryBound(to: VipsArea.self)))

        return HokusaiImage(backend: .vips(VipsBackend(takingOwnership: out)))
    }

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
