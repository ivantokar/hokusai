import Foundation
import CVips

extension HokusaiImage {
    /// Rotate image by specified angle
    public func rotate(angle: RotationAngle, background: [Double]? = nil) throws -> HokusaiImage {
        let pointer = try ensureVipsBackend().getPointer()
        let degrees = angle.degrees

        var output: UnsafeMutablePointer<CVips.VipsImage>?

        // For 90-degree multiples, use fast rotation
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
                // 0 or 360 degrees - return copy
                return self
            }

            let result = swift_vips_rot(pointer, &output, vipsAngle)

            guard result == 0, let out = output else {
                throw HokusaiError.vipsError(VipsBackend.getLastError())
            }

            return HokusaiImage(backend: .vips(VipsBackend(takingOwnership: out)))
        } else {
            // Use similarity transform for arbitrary angles
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
                    throw HokusaiError.vipsError(VipsBackend.getLastError())
                }

                return HokusaiImage(backend: .vips(VipsBackend(takingOwnership: out)))
            } else {
                let result = swift_vips_similarity(pointer, &output, degrees)

                guard result == 0, let out = output else {
                    throw HokusaiError.vipsError(VipsBackend.getLastError())
                }

                return HokusaiImage(backend: .vips(VipsBackend(takingOwnership: out)))
            }
        }
    }

    /// Rotate image by 90 degrees clockwise
    public func rotate90() throws -> HokusaiImage {
        return try rotate(angle: .degree90)
    }

    /// Rotate image by 180 degrees
    public func rotate180() throws -> HokusaiImage {
        return try rotate(angle: .degree180)
    }

    /// Rotate image by 270 degrees clockwise (90 degrees counter-clockwise)
    public func rotate270() throws -> HokusaiImage {
        return try rotate(angle: .degree270)
    }

    /// Flip image horizontally, vertically, or both
    public func flip(direction: FlipDirection) throws -> HokusaiImage {
        let pointer = try ensureVipsBackend().getPointer()

        var output: UnsafeMutablePointer<CVips.VipsImage>?

        switch direction {
        case .horizontal:
            let result = swift_vips_flip(pointer, &output, VIPS_DIRECTION_HORIZONTAL)

            guard result == 0, let out = output else {
                throw HokusaiError.vipsError(VipsBackend.getLastError())
            }

            return HokusaiImage(backend: .vips(VipsBackend(takingOwnership: out)))

        case .vertical:
            let result = swift_vips_flip(pointer, &output, VIPS_DIRECTION_VERTICAL)

            guard result == 0, let out = output else {
                throw HokusaiError.vipsError(VipsBackend.getLastError())
            }

            return HokusaiImage(backend: .vips(VipsBackend(takingOwnership: out)))

        case .both:
            // Flip horizontal then vertical
            let horizontalFlipped = try flip(direction: .horizontal)
            return try horizontalFlipped.flip(direction: .vertical)
        }
    }

    /// Flip image horizontally (mirror)
    public func flipHorizontal() throws -> HokusaiImage {
        return try flip(direction: .horizontal)
    }

    /// Flip image vertically
    public func flipVertical() throws -> HokusaiImage {
        return try flip(direction: .vertical)
    }

    /// Auto-rotate based on EXIF orientation
    public func autoRotate() throws -> HokusaiImage {
        let pointer = try ensureVipsBackend().getPointer()

        var output: UnsafeMutablePointer<CVips.VipsImage>?

        let result = swift_vips_autorot(pointer, &output)

        guard result == 0, let out = output else {
            throw HokusaiError.vipsError(VipsBackend.getLastError())
        }

        return HokusaiImage(backend: .vips(VipsBackend(takingOwnership: out)))
    }
}
