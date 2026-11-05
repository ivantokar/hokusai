import Foundation
import CVips

// Advanced filters (#26). Each is one reviewed operation with a typed contract; none is a
// generic libvips dispatch. Colour operations leave alpha alone and keep the sample type.

extension NativeImage {
    /// Convolves the colour bands, leaving alpha unchanged.
    ///
    /// The kernel's `offset` is on the 0...255 scale and is scaled for 16-bit images. libvips
    /// clips to the sample range, and edge pixels read the nearest edge pixel.
    func convolved(_ kernel: ConvolutionKernel) throws -> NativeImage {
        try onColourBands("convolve") { colour in
            let offset = kernel.offset * (colour.bandMaximum > 1 ? colour.bandMaximum / 255 : 1 / 255)
            return try kernel.values.withUnsafeBufferPointer { values in
                try colour.applying("convolve") {
                    swift_vips_conv_matrix($0, $1, values.baseAddress, Int32(kernel.width), Int32(kernel.height), kernel.scale, offset)
                }
            }
        }
    }

    /// `sample × multiply + add` on the colour bands; `add` is on the 0...255 scale. Alpha is kept.
    func linear(multiply: Double, add: Double) throws -> NativeImage {
        try onColourBands("linear") { colour in
            let scaledAdd = add * (colour.bandMaximum > 1 ? colour.bandMaximum / 255 : 1 / 255)
            let result = try colour.applying("linear") { swift_vips_linear1($0, $1, multiply, scaledAdd) }
            return result
        }
    }

    /// Applies a 3×3 colour matrix in sRGB; alpha is kept and the sample type is unchanged.
    func recombined(_ matrix: ColorMatrix) throws -> NativeImage {
        let rgb = try asRGBColour()
        return try rgb.onColourBands("recombine") { colour in
            try matrix.values.withUnsafeBufferPointer { values in
                try colour.applying("recombine") { swift_vips_recomb_matrix($0, $1, values.baseAddress, 3, 3) }
            }
        }
    }

    /// Converts to sRGB with three colour bands (plus alpha when there was one).
    fileprivate func asRGBColour() throws -> NativeImage {
        let interpretation = swift_vips_image_get_interpretation(pointer)
        let alpha = hasAlpha
        let colourBands = bands - (alpha ? 1 : 0)
        let isRGB = interpretation == VIPS_INTERPRETATION_sRGB.rawValue || interpretation == VIPS_INTERPRETATION_RGB16.rawValue
        if isRGB, colourBands == 3 { return self }
        return try applying("convert to sRGB") { swift_vips_colourspace_srgb($0, $1) }
    }

    /// Replaces each sample with the minimum (`dilate == false`) or maximum of a square window
    /// of side `2 × radius + 1`, band by band. Alpha is kept.
    func morphed(radius: Int, dilate: Bool) throws -> NativeImage {
        let side = 2 * radius + 1
        let rank = dilate ? side * side - 1 : 0
        return try onColourBands(dilate ? "dilate" : "erode") { colour in
            try colour.applying(dilate ? "dilate" : "erode") { swift_vips_rank($0, $1, Int32(side), Int32(side), Int32(rank)) }
        }
    }

    /// The strength of change in luminance, as one channel in the image's sample type. Alpha is kept.
    func edgeStrength(_ detector: EdgeDetector) throws -> NativeImage {
        let original = bandFormat
        return try onColourBands("edges") { colour in
            // Edges are measured on luminance in the 8-bit or 16-bit range of the source.
            let grey = try colour.convertToGrayscale()
            let edge: NativeImage
            switch detector {
            case .sobel: edge = try grey.applying("edges") { swift_vips_sobel($0, $1) }
            case .scharr: edge = try grey.applying("edges") { swift_vips_scharr($0, $1) }
            case .prewitt: edge = try grey.applying("edges") { swift_vips_prewitt($0, $1) }
            case .canny(let sigma): edge = try grey.applying("edges") { swift_vips_canny($0, $1, sigma) }
            }
            return try edge.castRounded(to: original, operation: "edges")
        }
    }

    /// One channel of the image as a single grey band; the image is first read as sRGB.
    func channel(_ channel: Channel) throws -> NativeImage {
        if channel == .alpha {
            guard hasAlpha else {
                throw HokusaiError.invalidOption(name: "channel", reason: "the image has no alpha channel")
            }
            return try applying("extract channel") { swift_vips_extract_band($0, $1, Int32(bands - 1), 1) }
                .tagged(as: bandFormat == Int32(VIPS_FORMAT_USHORT.rawValue) ? VIPS_INTERPRETATION_GREY16 : VIPS_INTERPRETATION_B_W)
        }
        let rgb = try asRGBColour().removeAlpha()
        let grey16 = rgb.bandFormat == Int32(VIPS_FORMAT_USHORT.rawValue)
        let band: NativeImage
        switch channel {
        case .red: band = try rgb.applying("extract channel") { swift_vips_extract_band($0, $1, 0, 1) }
        case .green: band = try rgb.applying("extract channel") { swift_vips_extract_band($0, $1, 1, 1) }
        case .blue: band = try rgb.applying("extract channel") { swift_vips_extract_band($0, $1, 2, 1) }
        case .luminance: return try rgb.convertToGrayscale()
        case .alpha: preconditionFailure("handled above")
        }
        return try band.tagged(as: grey16 ? VIPS_INTERPRETATION_GREY16 : VIPS_INTERPRETATION_B_W)
    }

    /// Replaces this image's alpha with the luminance of `mask`, which must have the same size.
    ///
    /// White is opaque and black transparent. An existing alpha channel is replaced, and the
    /// mask is scaled to this image's sample range.
    func replacingAlpha(with mask: NativeImage) throws -> NativeImage {
        guard width == mask.width, height == mask.height else {
            throw HokusaiError.invalidOption(
                name: "mask", reason: "must be \(width)×\(height) like the image, but is \(mask.width)×\(mask.height); resize one of them first")
        }
        // A mask's own transparency does not count: its colour is what it says.
        let luminance = try mask.channel(.luminance)
        let target = Int32(VIPS_FORMAT_USHORT.rawValue) == bandFormat ? VIPS_INTERPRETATION_GREY16 : VIPS_INTERPRETATION_B_W
        let alpha = try luminance.applying("join alpha") { swift_vips_colourspace($0, $1, target) }
            .castRounded(to: bandFormat, operation: "join alpha")
        return try Self.bandjoin([try removeAlpha(), alpha], operation: "join alpha")
    }

    fileprivate func tagged(as interpretation: VipsInterpretation) throws -> NativeImage {
        try applying("extract channel") { swift_vips_set_interpretation($0, $1, Int32(interpretation.rawValue)) }
    }
}
