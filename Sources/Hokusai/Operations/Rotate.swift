import Foundation
import CVips

extension HokusaiImage {
    /// Rotates this image by a right angle or arbitrary number of degrees.
    ///
    /// Multiples of 90 use libvips' lossless orientation operation. Other
    /// angles use a similarity transform and may expose `background` at corners.
    public func rotate(angle: RotationAngle, background: [Double]? = nil) throws -> HokusaiImage {
        HokusaiImage(native: try native().rotate(angle: angle, background: background))
    }

    /// Rotates the image 90 degrees clockwise.
    public func rotate90() throws -> HokusaiImage {
        return try rotate(angle: .degree90)
    }

    /// Rotates the image 180 degrees.
    public func rotate180() throws -> HokusaiImage {
        return try rotate(angle: .degree180)
    }

    /// Rotates the image 270 degrees clockwise, or 90 degrees counter-clockwise.
    public func rotate270() throws -> HokusaiImage {
        return try rotate(angle: .degree270)
    }

    /// Mirrors the image across one or both axes.
    public func flip(direction: FlipDirection) throws -> HokusaiImage {
        HokusaiImage(native: try native().flip(direction: direction))
    }

    /// Mirrors the image from left to right.
    public func flipHorizontal() throws -> HokusaiImage {
        return try flip(direction: .horizontal)
    }

    /// Mirrors the image from top to bottom.
    public func flipVertical() throws -> HokusaiImage {
        return try flip(direction: .vertical)
    }

    /// Applies the source EXIF orientation, if present.
    public func autoRotate() throws -> HokusaiImage {
        HokusaiImage(native: try native().autoRotate())
    }
}

extension NativeImage {
    /// Rotates for the legacy image handle; see `rotate(degrees:background:interpolation:)`.
    func rotate(angle: RotationAngle, background: [Double]?) throws -> NativeImage {
        try rotate(degrees: angle.degrees, background: background ?? [0, 0, 0, 0], interpolation: .bilinear)
    }

    /// Mirrors the image across one or both axes.
    func flip(direction: FlipDirection) throws -> NativeImage {
        switch direction {
        case .horizontal: try mirrored(VIPS_DIRECTION_HORIZONTAL, operation: "flip")
        case .vertical: try mirrored(VIPS_DIRECTION_VERTICAL, operation: "flip")
        case .both: try mirrored(VIPS_DIRECTION_HORIZONTAL, operation: "flip").mirrored(VIPS_DIRECTION_VERTICAL, operation: "flip")
        }
    }

    /// Applies the source EXIF orientation, if present.
    func autoRotate() throws -> NativeImage {
        try autoOrient()
    }
}
