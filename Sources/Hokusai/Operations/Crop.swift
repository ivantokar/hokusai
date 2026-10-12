import Foundation
import CVips

extension HokusaiImage {
    /// Extracts a rectangular region from this legacy image handle.
    ///
    /// Coordinates are measured from the current top-left corner. The returned
    /// handle owns a new native image; this source handle is not mutated.
    public func crop(left: Int, top: Int, width: Int, height: Int) throws -> HokusaiImage {
        HokusaiImage(native: try native().crop(left: left, top: top, width: width, height: height))
    }

    /// Extracts the rectangle described by ``CropOptions``.
    public func crop(options: CropOptions) throws -> HokusaiImage {
        return try crop(
            left: options.left,
            top: options.top,
            width: options.width,
            height: options.height
        )
    }

    /// Trims border pixels similar to the image background.
    ///
    /// The compatibility `background` parameter is intentionally rejected:
    /// libvips' implemented path uses its detected background instead.
    public func trim(threshold: Double = 10.0, background: [Double]? = nil) throws -> HokusaiImage {
        HokusaiImage(native: try native().trim(threshold: threshold, background: background))
    }
}

extension NativeImage {
    /// Extracts a rectangular region from this image.
    ///
    /// Coordinates are measured from the current top-left corner. The returned
    /// image is new; the receiver is not mutated.
    func crop(left: Int, top: Int, width: Int, height: Int) throws -> NativeImage {

        var output: UnsafeMutablePointer<CVips.VipsImage>?

        let result = swift_vips_extract_area(
            pointer,
            &output,
            Int32(left),
            Int32(top),
            Int32(width),
            Int32(height)
        )

        guard result == 0, let out = output else {
            VipsBackend.discardPartialImage(output)
            throw HokusaiError.vipsError(VipsBackend.getLastError())
        }

        return NativeImage(takingOwnership: out)
    }

    /// Produces a target-sized crop using an anchor or libvips smart-crop mode.
    func smartCrop(width: Int, height: Int, position: Position) throws -> NativeImage {
        let currentWidth = self.width
        let currentHeight = self.height

        // Avoid native work when crop geometry already matches the image.
        if currentWidth == width && currentHeight == height {
            return self
        }

        var output: UnsafeMutablePointer<CVips.VipsImage>?

        switch position {
        case .attention:
            // Ask libvips to retain the region it considers visually salient.
            let result = swift_vips_smartcrop(
                pointer,
                &output,
                Int32(width),
                Int32(height),
                VIPS_INTERESTING_ATTENTION
            )

            guard result == 0, let out = output else {
                VipsBackend.discardPartialImage(output)
                throw HokusaiError.vipsError(VipsBackend.getLastError())
            }

            return NativeImage(takingOwnership: out)

        case .entropy:
            // Ask libvips to retain the region with the most visual detail.
            let result = swift_vips_smartcrop(
                pointer,
                &output,
                Int32(width),
                Int32(height),
                VIPS_INTERESTING_ENTROPY
            )

            guard result == 0, let out = output else {
                VipsBackend.discardPartialImage(output)
                throw HokusaiError.vipsError(VipsBackend.getLastError())
            }

            return NativeImage(takingOwnership: out)

        default:
            // Fixed anchors resolve to deterministic top-left coordinates.
            let (left, top) = calculateCropPosition(
                imageWidth: currentWidth,
                imageHeight: currentHeight,
                targetWidth: width,
                targetHeight: height,
                position: position
            )

            return try crop(left: left, top: top, width: width, height: height)
        }
    }

    /// Trims border pixels similar to the image background.
    ///
    /// The compatibility `background` parameter is intentionally rejected:
    /// libvips' implemented path uses its detected background instead.
    func trim(threshold: Double, background: [Double]?) throws -> NativeImage {
        guard threshold.isFinite, threshold >= 0 else {
            throw HokusaiError.invalidOperation("Trim threshold must be finite and non-negative")
        }
        var left: Int32 = 0
        var top: Int32 = 0
        var width: Int32 = 0
        var height: Int32 = 0
        // The legacy background parameter was never implemented. Do not accept
        // it silently: callers should use the 1.0 `Hokusai.trim(threshold:)`.
        if background != nil {
            throw HokusaiError.unsupportedFormat("trim background is not supported")
        }
        guard swift_vips_find_trim(pointer, &left, &top, &width, &height, threshold) == 0 else {
            throw HokusaiError.vipsError(VipsBackend.getLastError())
        }
        return try crop(left: Int(left), top: Int(top), width: Int(width), height: Int(height))
    }

    // MARK: - Private Helpers

    /// Resolves a deterministic anchor into a clamped top-left crop coordinate.
    private func calculateCropPosition(
        imageWidth: Int,
        imageHeight: Int,
        targetWidth: Int,
        targetHeight: Int,
        position: Position
    ) -> (left: Int, top: Int) {
        let xOffset = (imageWidth - targetWidth) / 2
        let yOffset = (imageHeight - targetHeight) / 2

        switch position {
        case .center:
            return (xOffset, yOffset)
        case .top:
            return (xOffset, 0)
        case .bottom:
            return (xOffset, max(0, imageHeight - targetHeight))
        case .left:
            return (0, yOffset)
        case .right:
            return (max(0, imageWidth - targetWidth), yOffset)
        case .topLeft:
            return (0, 0)
        case .topRight:
            return (max(0, imageWidth - targetWidth), 0)
        case .bottomLeft:
            return (0, max(0, imageHeight - targetHeight))
        case .bottomRight:
            return (max(0, imageWidth - targetWidth), max(0, imageHeight - targetHeight))
        default:
            return (xOffset, yOffset)
        }
    }
}
