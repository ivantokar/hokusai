import Foundation
import CVips

extension NativeImage {
    /// Measures this image: per-band statistics, entropy, sharpness, and the
    /// dominant colour.
    ///
    /// The image is converted once to 8-bit sRGB (or grey) and evaluated into
    /// memory, so the pipeline behind it runs a single time; every measurement
    /// then reads that result. The one materialised copy costs about the size
    /// of the 8-bit image.
    func statistics(context: EvaluationContext) throws -> ImageStatistics {
        func step(_ source: NativeImage, _ body: (Pointer, UnsafeMutablePointer<Pointer?>) -> Int32) throws -> NativeImage {
            try NativeImage.producing({ body(source.pointer, $0) }, failure: { .nativeTransform("stats") })
        }
        func scalar(_ source: NativeImage, _ body: (Pointer, UnsafeMutablePointer<Double>) -> Int32) throws -> Double {
            var value = 0.0
            guard body(source.pointer, &value) == 0 else { throw HokusaiError.nativeTransform("stats") }
            return value
        }

        let interpretation = Int32(swift_vips_image_get_interpretation(pointer))
        let isGrey = interpretation == Int32(VIPS_INTERPRETATION_B_W.rawValue)
            || interpretation == Int32(VIPS_INTERPRETATION_GREY16.rawValue)

        // Normalise to 8-bit sRGB (or grey) so values are comparable everywhere.
        let converted = try step(self) { isGrey ? swift_vips_colourspace_bw($0, $1) : swift_vips_colourspace_srgb($0, $1) }
        let eightBit = try step(converted) { swift_vips_cast_uchar($0, $1) }
        let colourBands = isGrey ? 1 : 3
        guard eightBit.bands == colourBands || eightBit.bands == colourBands + 1 else {
            throw HokusaiError.transform(FailureContext(
                operation: "stats", reason: "statistics need an image that converts to sRGB or grey, found \(eightBit.bands) bands"))
        }
        let hasAlpha = eightBit.bands == colourBands + 1

        // Evaluate the pipeline once; everything below reads this copy.
        guard let copy = swift_vips_copy_memory(eightBit.pointer) else { throw HokusaiError.nativeTransform("stats") }
        let base = NativeImage(takingOwnership: copy)
        try context.checkCancellation()

        // Per-band statistics from one pass.
        let matrix = try step(base) { swift_vips_stats($0, $1) }
        var matrixSize = 0
        guard let raw = vips_image_write_to_memory(matrix.pointer, &matrixSize) else { throw HokusaiError.nativeTransform("stats") }
        defer { g_free(raw) }
        let columns = 10
        let values = raw.bindMemory(to: Double.self, capacity: matrixSize / MemoryLayout<Double>.size)
        guard matrixSize == (base.bands + 1) * columns * MemoryLayout<Double>.size else { throw HokusaiError.nativeTransform("stats") }

        // A deviation needs two or more pixels; libvips reports NaN below that.
        let hasSpread = base.width * base.height > 1
        let kinds: [ChannelStatistics.Kind] = isGrey ? [.grey, .alpha] : [.red, .green, .blue, .alpha]
        let channels = (0..<base.bands).map { band -> ChannelStatistics in
            // Row 0 pools every band; band rows follow.
            let row = values + (band + 1) * columns
            return ChannelStatistics(
                kind: kinds[band],
                minimum: row[0], minimumLocation: .init(x: Int(row[6]), y: Int(row[7])),
                maximum: row[1], maximumLocation: .init(x: Int(row[8]), y: Int(row[9])),
                sum: row[2], sumOfSquares: row[3], mean: row[4],
                standardDeviation: hasSpread && row[5].isFinite ? row[5] : 0)
        }
        let isOpaque = !hasAlpha || (channels.last?.minimum ?? 255) >= 255

        // Luminance, ignoring alpha, for entropy and sharpness.
        let colour = try NativeImage.producing({ swift_vips_extract_band(base.pointer, $0, 0, Int32(colourBands)) }, failure: { .nativeTransform("stats") })
        let luminance = isGrey ? colour : try step(try step(colour) { swift_vips_colourspace_bw($0, $1) }) { swift_vips_cast_uchar($0, $1) }
        try context.checkCancellation()

        let histogram = try step(luminance) { swift_vips_hist_find($0, $1) }
        let entropy = try scalar(histogram) { swift_vips_hist_entropy($0, $1) }
        let sharpness = hasSpread ? try scalar(luminance) { swift_vips_laplacian_deviation($0, $1) } : 0
        try context.checkCancellation()

        return ImageStatistics(
            channels: channels,
            isOpaque: isOpaque,
            entropy: entropy,
            sharpness: sharpness,
            dominantColor: try dominantColor(of: isGrey ? try step(colour) { swift_vips_colourspace_srgb($0, $1) } : colour))
    }

    /// The centre of the fullest cell of a 16-level-per-channel colour histogram.
    private func dominantColor(of rgb: NativeImage) throws -> Color? {
        let histogram = try NativeImage.producing({ swift_vips_hist_find_ndim16(rgb.pointer, $0) }, failure: { .nativeTransform("stats") })
        guard histogram.width == 16, histogram.height == 16, histogram.bands == 16,
              Int32(swift_vips_image_get_band_format(histogram.pointer)) == Int32(VIPS_FORMAT_UINT.rawValue) else {
            return nil
        }
        var size = 0
        guard let raw = vips_image_write_to_memory(histogram.pointer, &size) else { throw HokusaiError.nativeTransform("stats") }
        defer { g_free(raw) }
        let cells = 16 * 16 * 16
        guard size == cells * MemoryLayout<UInt32>.size else { return nil }
        let counts = raw.bindMemory(to: UInt32.self, capacity: cells)

        // Cells are laid out by y, then x, then band: x holds the first colour
        // band's level, y the second, and the band index the third.
        var best = 0
        for index in 1..<cells where counts[index] > counts[best] { best = index }
        guard counts[best] > 0 else { return nil }
        let blue = best % 16, red = (best / 16) % 16, green = best / 256
        func centre(_ level: Int) -> Double { Double(level * 16 + 8) / 255 }
        return Color(red: centre(red), green: centre(green), blue: centre(blue))
    }
}
