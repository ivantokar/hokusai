import CVips

/// Internal bridge from typed thumbnail options to libvips arguments.
///
/// Every thumbnail entry point validates here. This keeps CVips types out of
/// the public model layer and makes all callers apply the same dimension rules.

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

    /// Validates public options before they cross the C boundary.
    ///
    /// Smart-crop modes need both dimensions. Without a height, the shim uses
    /// the `0` sentinel to apply only the width constraint.
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

    /// Ensures a positive Swift integer can be represented by libvips.
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
