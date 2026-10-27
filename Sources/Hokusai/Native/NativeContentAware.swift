import Foundation
import CVips

extension NativeImage {
    /// Crops away the border found by `vips_find_trim`.
    ///
    /// The scan happens here, when the step is lowered, so it always sees the
    /// pixels produced by the steps before it. An image with no content (all
    /// background) comes back unchanged.
    func trimmed(_ options: TrimOptions) throws -> NativeImage {
        let background = try trimBackground(options.background)
        var left: Int32 = 0, top: Int32 = 0, width: Int32 = 0, height: Int32 = 0
        let status = background.withUnsafeBufferPointer {
            swift_vips_find_trim(
                pointer, &left, &top, &width, &height, options.threshold, $0.baseAddress, Int32($0.count),
                options.lineArt ? 1 : 0)
        }
        guard status == 0 else { throw HokusaiError.nativeTransform("trim") }
        guard width > 0, height > 0 else { return self }

        // Margins grow the box on every side, never past the image.
        let margin = options.margin
        let x0 = max(0, Int(left) - margin)
        let y0 = max(0, Int(top) - margin)
        let x1 = min(self.width, Int(left) + Int(width) + margin)
        let y1 = min(self.height, Int(top) + Int(height) + margin)
        if x0 == 0, y0 == 0, x1 == self.width, y1 == self.height { return self }
        return try crop(left: x0, top: y0, width: x1 - x0, height: y1 - y0)
    }

    /// The background values `find_trim` compares against: one per colour band, in the image's own range.
    private func trimBackground(_ background: TrimBackground) throws -> [Double] {
        let colourBands = hasAlpha ? bands - 1 : bands
        switch background {
        case .topLeft:
            return Array(try pixel(x: 0, y: 0).prefix(colourBands))
        case .color(let color):
            let scale: Double
            switch bandFormat {
            case Int32(VIPS_FORMAT_UCHAR.rawValue): scale = 1
            case Int32(VIPS_FORMAT_USHORT.rawValue): scale = 257
            default: scale = 1.0 / 255
            }
            let rgb = try color.rgba8().prefix(3).map { $0 * scale }
            switch colourBands {
            case 3: return rgb
            case 1: return [(0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2])]
            default:
                throw HokusaiError.invalidOption(name: "background", reason: "an explicit colour needs a grey or RGB image")
            }
        }
    }

    /// A `width` × `height` region chosen by libvips' interest measure. Both must fit the image.
    func smartCrop(width: Int, height: Int, strategy: SmartCropStrategy) throws -> NativeImage {
        if width == self.width && height == self.height { return self }
        let interesting: VipsInteresting = switch strategy {
        case .attention: VIPS_INTERESTING_ATTENTION
        case .entropy: VIPS_INTERESTING_ENTROPY
        }
        return try applying("smart crop") { swift_vips_smartcrop($0, $1, Int32(width), Int32(height), interesting) }
    }
}
