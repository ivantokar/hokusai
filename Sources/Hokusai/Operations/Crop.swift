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
            throw HokusaiError.nativeTransform("extract")
        }

        return NativeImage(takingOwnership: out)
    }

    /// Trims border pixels similar to the image background.
    ///
    /// The compatibility `background` parameter is intentionally rejected:
    /// libvips' implemented path uses its detected background instead.
    func trim(threshold: Double, background: [Double]?) throws -> NativeImage {
        guard threshold.isFinite, threshold >= 0 else {
            throw HokusaiError.invalidOption(name: "threshold", reason: "must be a finite value greater than or equal to zero")
        }
        var left: Int32 = 0
        var top: Int32 = 0
        var width: Int32 = 0
        var height: Int32 = 0
        // The legacy background parameter was never implemented. Do not accept
        // it silently: callers should use the 1.0 `Hokusai.trim(threshold:)`.
        if background != nil {
            throw HokusaiError.unsupported(feature: "trim background", reason: "libvips detects the background itself")
        }
        guard swift_vips_find_trim(pointer, &left, &top, &width, &height, threshold) == 0 else {
            throw HokusaiError.nativeTransform("trim")
        }
        return try crop(left: Int(left), top: Int(top), width: Int(width), height: Int(height))
    }
}
