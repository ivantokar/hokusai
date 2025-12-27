import Foundation
import CVips

extension HokusaiImage {
    /// Extract a rectangular region from the image
    public func crop(left: Int, top: Int, width: Int, height: Int) throws -> HokusaiImage {
        let pointer = try ensureVipsBackend().getPointer()

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
            throw HokusaiError.vipsError(VipsBackend.getLastError())
        }

        return HokusaiImage(backend: .vips(VipsBackend(takingOwnership: out)))
    }

    /// Extract a rectangular region using CropOptions
    public func crop(options: CropOptions) throws -> HokusaiImage {
        return try crop(
            left: options.left,
            top: options.top,
            width: options.width,
            height: options.height
        )
    }

    /// Smart crop to target dimensions using attention or entropy detection
    func smartCrop(width: Int, height: Int, position: Position) throws -> HokusaiImage {
        let pointer = try ensureVipsBackend().getPointer()
        let currentWidth = try ensureVipsBackend().getWidth()
        let currentHeight = try ensureVipsBackend().getHeight()

        // If already the right size, return as-is
        if currentWidth == width && currentHeight == height {
            return self
        }

        var output: UnsafeMutablePointer<CVips.VipsImage>?

        switch position {
        case .attention:
            // Use smartcrop with attention strategy
            let result = swift_vips_smartcrop(
                pointer,
                &output,
                Int32(width),
                Int32(height),
                VIPS_INTERESTING_ATTENTION
            )

            guard result == 0, let out = output else {
                throw HokusaiError.vipsError(VipsBackend.getLastError())
            }

            return HokusaiImage(backend: .vips(VipsBackend(takingOwnership: out)))

        case .entropy:
            // Use smartcrop with entropy strategy
            let result = swift_vips_smartcrop(
                pointer,
                &output,
                Int32(width),
                Int32(height),
                VIPS_INTERESTING_ENTROPY
            )

            guard result == 0, let out = output else {
                throw HokusaiError.vipsError(VipsBackend.getLastError())
            }

            return HokusaiImage(backend: .vips(VipsBackend(takingOwnership: out)))

        default:
            // Manual crop based on position
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

    /// Trim "boring" edges from the image
    public func trim(threshold: Double = 10.0, background: [Double]? = nil) throws -> HokusaiImage {
        // TODO: Implement trim functionality
        // This requires using vips_find_trim to detect trim boundaries,
        // then using crop to extract the trimmed region

        // For now, return a copy
        return self
    }

    // MARK: - Private Helpers

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
