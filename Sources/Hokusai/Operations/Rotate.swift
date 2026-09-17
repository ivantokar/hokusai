import Foundation
import CVips

extension HokusaiImage {
    /// Rotates this image by a right angle or arbitrary number of degrees.
    ///
    /// Multiples of 90 use libvips' lossless orientation operation. Other
    /// angles use a similarity transform and may expose `background` at corners.
    public func rotate(angle: RotationAngle, background: [Double]? = nil) throws -> HokusaiImage {
        let pointer = try ensureVipsBackend().getPointer()
        let degrees = angle.degrees

        var output: UnsafeMutablePointer<CVips.VipsImage>?

        // Right-angle rotations avoid interpolation and are the cheapest path.
        if degrees.truncatingRemainder(dividingBy: 90) == 0 {
            let vipsAngle: VipsAngle

            switch Int(degrees) % 360 {
            case 90, -270:
                vipsAngle = VIPS_ANGLE_D90
            case 180, -180:
                vipsAngle = VIPS_ANGLE_D180
            case 270, -90:
                vipsAngle = VIPS_ANGLE_D270
            default:
                // A full turn changes no pixels, so preserve the existing handle.
                return self
            }

            let result = swift_vips_rot(pointer, &output, vipsAngle)

            guard result == 0, let out = output else {
                VipsBackend.discardPartialImage(output)
                throw HokusaiError.vipsError(VipsBackend.getLastError())
            }

            return HokusaiImage(backend: .vips(VipsBackend(takingOwnership: out)))
        } else {
            // Arbitrary rotations require interpolation through a similarity transform.
            if let bg = background {
                let bgArray = bg.withUnsafeBufferPointer { ptr in
                    swift_vips_array_double_new(ptr.baseAddress, Int32(bg.count))
                }

                guard let bgPtr = bgArray else {
                    throw HokusaiError.vipsError("Failed to create background array")
                }

                let result = swift_vips_similarity_background(pointer, &output, degrees, bgPtr)

                vips_area_unref(UnsafeMutablePointer(mutating: UnsafeRawPointer(bgPtr).assumingMemoryBound(to: VipsArea.self)))

                guard result == 0, let out = output else {
                    VipsBackend.discardPartialImage(output)
                    throw HokusaiError.vipsError(VipsBackend.getLastError())
                }

                return HokusaiImage(backend: .vips(VipsBackend(takingOwnership: out)))
            } else {
                let result = swift_vips_similarity(pointer, &output, degrees)

                guard result == 0, let out = output else {
                    VipsBackend.discardPartialImage(output)
                    throw HokusaiError.vipsError(VipsBackend.getLastError())
                }

                return HokusaiImage(backend: .vips(VipsBackend(takingOwnership: out)))
            }
        }
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
        let pointer = try ensureVipsBackend().getPointer()

        var output: UnsafeMutablePointer<CVips.VipsImage>?

        switch direction {
        case .horizontal:
            let result = swift_vips_flip(pointer, &output, VIPS_DIRECTION_HORIZONTAL)

            guard result == 0, let out = output else {
                VipsBackend.discardPartialImage(output)
                throw HokusaiError.vipsError(VipsBackend.getLastError())
            }

            return HokusaiImage(backend: .vips(VipsBackend(takingOwnership: out)))

        case .vertical:
            let result = swift_vips_flip(pointer, &output, VIPS_DIRECTION_VERTICAL)

            guard result == 0, let out = output else {
                VipsBackend.discardPartialImage(output)
                throw HokusaiError.vipsError(VipsBackend.getLastError())
            }

            return HokusaiImage(backend: .vips(VipsBackend(takingOwnership: out)))

        case .both:
            // Applying both single-axis operations keeps native behavior explicit.
            let horizontalFlipped = try flip(direction: .horizontal)
            return try horizontalFlipped.flip(direction: .vertical)
        }
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
        let pointer = try ensureVipsBackend().getPointer()

        var output: UnsafeMutablePointer<CVips.VipsImage>?

        let result = swift_vips_autorot(pointer, &output)

        guard result == 0, let out = output else {
            VipsBackend.discardPartialImage(output)
            throw HokusaiError.vipsError(VipsBackend.getLastError())
        }

        return HokusaiImage(backend: .vips(VipsBackend(takingOwnership: out)))
    }
}
