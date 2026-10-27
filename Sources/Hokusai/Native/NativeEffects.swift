import Foundation
import CVips

// MARK: - Band handling

extension NativeImage {
    /// The libvips band format of this image.
    var bandFormat: Int32 { Int32(swift_vips_image_get_band_format(pointer)) }

    /// The largest value of an integer band, or 1 for float images.
    var bandMaximum: Double {
        switch bandFormat {
        case Int32(VIPS_FORMAT_UCHAR.rawValue): 255
        case Int32(VIPS_FORMAT_USHORT.rawValue): 65535
        default: 1
        }
    }

    /// Splits trailing alpha from the colour bands.
    private func splitAlpha() throws -> (colour: NativeImage, alpha: NativeImage?) {
        guard hasAlpha else { return (self, nil) }
        let colour = try applying("extract colour") { swift_vips_extract_band($0, $1, 0, Int32(bands - 1)) }
        let alpha = try applying("extract alpha") { swift_vips_extract_band($0, $1, Int32(bands - 1), 1) }
        return (colour, alpha)
    }

    /// Joins `images` into one image, bands in order.
    private static func bandjoin(_ images: [NativeImage], operation: String) throws -> NativeImage {
        var pointers: [UnsafeMutablePointer<CVips.VipsImage>?] = images.map { $0.pointer }
        return try producing({ output in
            pointers.withUnsafeMutableBufferPointer { swift_vips_bandjoin($0.baseAddress, output, Int32($0.count)) }
        }, failure: { .nativeTransform(operation) })
    }

    /// Casts to `format`, rounding to nearest when a float becomes an integer.
    func castRounded(to format: Int32, operation: String) throws -> NativeImage {
        guard format != bandFormat else { return self }
        let isFloat = { (value: Int32) in value == Int32(VIPS_FORMAT_FLOAT.rawValue) || value == Int32(VIPS_FORMAT_DOUBLE.rawValue) }
        var base = self
        if isFloat(bandFormat), !isFloat(format) {
            base = try applying(operation) { swift_vips_linear1($0, $1, 1, 0.5) }
        }
        return try base.applying(operation) { swift_vips_cast($0, $1, format) }
    }

    /// Applies `body` to the colour bands only and puts alpha back unchanged.
    ///
    /// `body` may return a different band format; the result is cast back to
    /// this image's format so effects never change bit depth.
    func onColourBands(_ operation: String, _ body: (NativeImage) throws -> NativeImage) throws -> NativeImage {
        let original = bandFormat
        let (colour, alpha) = try splitAlpha()
        let processed = try body(colour).castRounded(to: original, operation: operation)
        guard let alpha else { return processed }
        return try Self.bandjoin([processed, alpha], operation: operation)
    }

    /// Applies `body` with alpha premultiplied, so transparent pixels do not
    /// bleed their (arbitrary) colour into their neighbours.
    func premultiplied(_ operation: String, _ body: (NativeImage) throws -> NativeImage) throws -> NativeImage {
        guard hasAlpha else { return try body(self) }
        let original = bandFormat
        let premultiplied = try applying(operation) { swift_vips_premultiply($0, $1) }
        let result = try body(premultiplied).applying(operation) { swift_vips_unpremultiply($0, $1) }
        return try result.castRounded(to: original, operation: operation)
    }
}

// MARK: - Blur and sharpen

extension BlurPrecision {
    fileprivate var vipsValue: Int32 {
        switch self {
        case .integer: Int32(VIPS_PRECISION_INTEGER.rawValue)
        case .float: Int32(VIPS_PRECISION_FLOAT.rawValue)
        case .approximate: Int32(VIPS_PRECISION_APPROXIMATE.rawValue)
        }
    }
}

extension NativeImage {
    func gaussianBlur(sigma: Double, precision: BlurPrecision, minAmplitude: Double) throws -> NativeImage {
        try premultiplied("blur") { image in
            try image.applying("blur") { swift_vips_gaussblur_full($0, $1, sigma, precision.vipsValue, minAmplitude) }
        }
    }

    /// Unsharp mask on luminance; libvips keeps alpha untouched.
    func sharpen(_ options: SharpenOptions) throws -> NativeImage {
        try applying("sharpen") {
            swift_vips_sharpen_full(
                $0, $1, options.sigma, options.threshold, options.maxBrightening, options.maxDarkening, options.flat, options.jagged)
        }
    }
}

// MARK: - Colour

extension NativeImage {
    /// Desaturates to luminance but keeps the image's RGB(A) layout.
    ///
    /// Luminance is libvips' sRGB → B_W conversion, which works in linear
    /// light and re-encodes; alpha is carried through untouched. Use
    /// `convertToGrayscale` for a single colour channel.
    func grayscaleEffect() throws -> NativeImage {
        try convertToGrayscale().applying("grayscale") { swift_vips_colourspace_srgb($0, $1) }
    }

    /// Converts to a single colour channel (plus alpha if present).
    func convertToGrayscale() throws -> NativeImage {
        try applying("convert to grayscale") { swift_vips_colourspace_bw($0, $1) }
    }

    /// Maps luminance into `rgba`: white becomes the tint, black stays black.
    /// Existing alpha is preserved.
    func tint(_ rgba: [Double]) throws -> NativeImage {
        let scale = [rgba[0] / 255, rgba[1] / 255, rgba[2] / 255]
        let grey = try grayscaleEffect()
        return try grey.onColourBands("tint") { colour in
            try colour.applying("tint") { swift_vips_linear_array($0, $1, scale, [0, 0, 0], 3) }
        }
    }

    /// Stretches the luminance range between two percentiles to the full
    /// range, clipping what lies outside. The same linear map is applied to
    /// every colour band, so hue is kept; alpha is untouched.
    func normalize(lower: Double, upper: Double) throws -> NativeImage {
        guard bandMaximum > 1 else {
            throw HokusaiError.unsupported(feature: "normalize", reason: "requires an 8- or 16-bit image")
        }
        let maximum = bandMaximum
        let (colour, _) = try splitAlpha()
        // Percentiles are read from an 8-bit luminance image.
        var luminance = try colour.applying("normalize") { swift_vips_colourspace_bw($0, $1) }
        luminance = try luminance.applying("normalize") { swift_vips_extract_band($0, $1, 0, 1) }
        if maximum > 255 {
            luminance = try luminance.applying("normalize") { swift_vips_linear1($0, $1, 255 / maximum, 0.5) }
            luminance = try luminance.applying("normalize") { swift_vips_cast($0, $1, Int32(VIPS_FORMAT_UCHAR.rawValue)) }
        }

        // `vips_percent` returns the value below which that share of pixels
        // lies, and the bin count (256) for 100, so the extremes use min/max.
        var low = 0.0
        var high = 0.0
        if lower <= 0 {
            guard swift_vips_min(luminance.pointer, &low) == 0 else { throw HokusaiError.nativeTransform("normalize") }
        } else {
            var threshold: Int32 = 0
            guard swift_vips_percent(luminance.pointer, lower, &threshold) == 0 else { throw HokusaiError.nativeTransform("normalize") }
            low = Double(threshold)
        }
        if upper >= 100 {
            guard swift_vips_max(luminance.pointer, &high) == 0 else { throw HokusaiError.nativeTransform("normalize") }
        } else {
            var threshold: Int32 = 0
            guard swift_vips_percent(luminance.pointer, upper, &threshold) == 0 else { throw HokusaiError.nativeTransform("normalize") }
            high = Double(threshold) - 1
        }
        // A flat image has nothing to stretch.
        guard high > low else { return self }

        // `low` and `high` are on the 8-bit scale; map them to this image's range.
        let lowValue = low * maximum / 255
        let highValue = high * maximum / 255
        let scale = maximum / (highValue - lowValue)
        let offset = -lowValue * scale
        return try onColourBands("normalize") { colour in
            let counts = Int32(colour.bands)
            return try colour.applying("normalize") {
                swift_vips_linear_array($0, $1, Array(repeating: scale, count: Int(counts)), Array(repeating: offset, count: Int(counts)), counts)
            }
        }
    }

    /// Contrast-limited adaptive histogram equalisation on each colour band.
    func clahe(width: Int, height: Int, maxSlope: Int) throws -> NativeImage {
        guard bandMaximum == 255 else {
            throw HokusaiError.unsupported(feature: "clahe", reason: "requires an 8-bit image")
        }
        return try onColourBands("clahe") { colour in
            try colour.applying("clahe") { swift_vips_hist_local($0, $1, Int32(width), Int32(height), Int32(maxSlope)) }
        }
    }

    /// `out = in ^ (1 / value)` on the colour bands; values above 1 brighten.
    func gamma(_ value: Double) throws -> NativeImage {
        try onColourBands("gamma") { colour in
            try colour.applying("gamma") { swift_vips_gamma($0, $1, value) }
        }
    }

    /// Inverts the colour bands; alpha is inverted too only when `alpha` is true.
    func negate(alpha: Bool) throws -> NativeImage {
        if alpha {
            return try applying("negate") { swift_vips_invert($0, $1) }
        }
        return try onColourBands("negate") { colour in
            try colour.applying("negate") { swift_vips_invert($0, $1) }
        }
    }

    /// Square median filter with an odd or even window of `size` pixels.
    func median(size: Int) throws -> NativeImage {
        try applying("median") { swift_vips_median($0, $1, Int32(size)) }
    }

    /// Black-and-white threshold.
    ///
    /// With `grayscale` the colour bands first become one luminance band, so
    /// the result has one colour channel; otherwise every colour band is
    /// thresholded on its own. `level` is on the 0...255 scale. Alpha is kept.
    func threshold(level: Double, grayscale: Bool) throws -> NativeImage {
        let source = grayscale ? try convertToGrayscale() : self
        let scaled = level * (source.bandMaximum > 1 ? source.bandMaximum / 255 : 1 / 255)
        return try source.onColourBands("threshold") { colour in
            let mask = try colour.applying("threshold") { swift_vips_moreeq_const1($0, $1, scaled) }
            // The comparison yields 0 or 255; 16-bit images need 0 or 65535.
            guard colour.bandMaximum > 255 else { return mask }
            return try mask.applying("threshold") { swift_vips_linear1($0, $1, 257, 0) }
        }
    }

    /// Brightness and saturation multipliers and a hue rotation in degrees,
    /// applied in LCH so lightness, chroma and hue move independently.
    func modulate(brightness: Double, saturation: Double, hue: Double) throws -> NativeImage {
        try onColourBands("modulate") { colour in
            let lch = try colour.applying("modulate") { swift_vips_colourspace($0, $1, VIPS_INTERPRETATION_LCH) }
            let adjusted = try lch.applying("modulate") {
                swift_vips_linear_array($0, $1, [brightness, saturation, 1], [0, 0, hue], 3)
            }
            return try adjusted.applying("modulate") { swift_vips_colourspace_srgb($0, $1) }
        }
    }
}

// MARK: - Alpha

extension NativeImage {
    /// Appends a constant alpha band of `opacity` (0...1) when there is none.
    func ensureAlpha(opacity: Double) throws -> NativeImage {
        if hasAlpha { return self }
        if opacity == 1 {
            return try applying("ensure alpha") { swift_vips_addalpha($0, $1) }
        }
        var value = [opacity * bandMaximum]
        return try applying("ensure alpha") { swift_vips_bandjoin_const($0, $1, &value, 1) }
    }

    /// Drops the alpha band without compositing; a no-op when there is none.
    func removeAlpha() throws -> NativeImage {
        guard hasAlpha else { return self }
        return try applying("remove alpha") { swift_vips_extract_band($0, $1, 0, Int32(bands - 1)) }
    }

    /// Composites over `background` and removes alpha; a no-op without alpha.
    func flatten(background rgba: [Double]) throws -> NativeImage {
        guard hasAlpha else { return self }
        // The fill covers the colour bands only; alpha is what is removed.
        let fill = Array(fill(rgba).dropLast())
        return try Self.withNativeArray(fill, operation: "flatten") { area in
            try applying("flatten") { swift_vips_flatten($0, $1, area) }
        }
    }
}
