import CVips

/// PURPOSE: Single home for thumbnail argument validation and the mapping
/// from public thumbnail types onto libvips types.
/// CONSTRAINTS:
/// - All thumbnail entry points (file, buffer, existing image, CLI via the
///   library) must validate through `ThumbnailArguments.validate`.
/// - Public model types must not expose libvips types; the mapping lives here
///   as an internal extension instead.

extension ThumbnailCrop {
    /// The libvips smart-crop strategy backing this public case.
    /// Exhaustive on purpose: adding a `ThumbnailCrop` case fails to compile
    /// until it is mapped here.
    var vipsInteresting: VipsInteresting {
        switch self {
        case .none: return VIPS_INTERESTING_NONE
        case .centre: return VIPS_INTERESTING_CENTRE
        case .attention: return VIPS_INTERESTING_ATTENTION
        case .entropy: return VIPS_INTERESTING_ENTROPY
        }
    }

    /// Raw value of ``vipsInteresting`` for the mapping-coverage test.
    /// CVips is an internal import, so members whose signature names a CVips
    /// type are not visible to the test target, even via @testable.
    var vipsInterestingRawValue: Int {
        Int(vipsInteresting.rawValue)
    }
}

enum ThumbnailArguments {
    /// Validated thumbnail dimensions, safe to hand to the C shim.
    /// `height == 0` means "no height bound" (the shim substitutes
    /// `VIPS_MAX_COORD` so only the width constrains the output).
    struct Validated {
        let width: Int32
        let height: Int32
        let crop: VipsInteresting
        let noRotate: Int32
    }

    static func validate(width: Int, options: ThumbnailOptions) throws -> Validated {
        let validWidth = try validateDimension(width, name: "width")

        let validHeight: Int32
        if let height = options.height {
            validHeight = try validateDimension(height, name: "height")
        } else {
            if options.crop != .none {
                throw HokusaiError.invalidDimensions(
                    "thumbnail crop strategies require an explicit height; set ThumbnailOptions.height")
            }
            validHeight = 0
        }

        return Validated(
            width: validWidth,
            height: validHeight,
            crop: options.crop.vipsInteresting,
            noRotate: options.noRotate ? 1 : 0
        )
    }

    private static func validateDimension(_ value: Int, name: String) throws -> Int32 {
        guard value > 0 else {
            throw HokusaiError.invalidDimensions("thumbnail \(name) must be greater than zero, got \(value)")
        }
        guard let converted = Int32(exactly: value) else {
            throw HokusaiError.invalidDimensions("thumbnail \(name) must be at most \(Int32.max), got \(value)")
        }
        return converted
    }
}
