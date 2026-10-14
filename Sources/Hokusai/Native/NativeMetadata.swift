import Foundation
import CVips

extension NativeImage {
    /// The typed source metadata of this freshly opened image.
    ///
    /// Reads only the header that opening populated; no pixels are decoded.
    /// Raw blocks are copied into owned `Data`, so the result is safe to use
    /// after the native image is released.
    func sourceMetadata(sourceByteSize: Int?) -> ImageMetadata {
        let loader = metadataString("vips-loader")
        let format = Self.sourceFormat(loader: loader, heifCompression: metadataString("heif-compression"))
        let pixelFormat = Self.sampleFormat(Int(swift_vips_image_get_band_format(pointer)))
        let isPNG = Self.loaderBase(loader) == "pngload"
        let isJPEG = Self.loaderBase(loader) == "jpegload"

        let pixel = PixelMetadata(
            channels: bands,
            hasAlpha: hasAlpha,
            interpretation: Self.interpretation(Int(swift_vips_image_get_interpretation(pointer))),
            sampleFormat: pixelFormat,
            bitsPerSample: metadataInt("bits-per-sample")
                ?? (pixelFormat == .unknown ? nil : Int(swift_vips_format_bits(swift_vips_image_get_band_format(pointer)))),
            isPalette: isPNG ? metadataInt("palette") != nil : nil
        )

        let progressive: Bool?
        if isJPEG {
            progressive = metadataInt("jpeg-multiscan").map { $0 != 0 }
        } else if isPNG {
            progressive = (metadataInt("interlaced") ?? 0) != 0
        } else {
            progressive = nil
        }

        let pageCount = pageCount
        let density = Self.density(xres: swift_vips_image_get_xres(pointer), yres: swift_vips_image_get_yres(pointer))

        return ImageMetadata(
            format: format,
            width: width,
            height: height,
            orientation: metadataInt("orientation").flatMap(ImageOrientation.init(nativeValue:)),
            pixel: pixel,
            density: density,
            densityUnit: density == nil ? nil : Self.resolutionUnit(metadataString("resolution-unit")),
            pages: PageMetadata(
                count: pageCount,
                height: pageCount > 1 ? metadataInt("page-height") : nil,
                primary: metadataInt("heif-primary"),
                subIFDCount: metadataInt("n-subifds")
            ),
            animation: pageCount > 1 ? animation() : nil,
            sourceByteSize: sourceByteSize,
            isProgressive: progressive,
            chromaSubsampling: isJPEG ? metadataString("jpeg-chroma-subsample") : nil,
            exif: metadataBlob(named: "exif-data"),
            iccProfile: metadataBlob(named: "icc-profile-data"),
            xmp: metadataBlob(named: "xmp-data"),
            iptc: metadataBlob(named: "iptc-data")
        )
    }

    // MARK: - Header readers

    private func metadataInt(_ name: String) -> Int? {
        var value: Int32 = 0
        return swift_vips_image_get_int_field(pointer, name, &value) == 0 ? Int(value) : nil
    }

    private func metadataString(_ name: String) -> String? {
        swift_vips_image_get_string_field(pointer, name).map { String(cString: $0) }
    }

    /// Animation facts, only when the source carries frame delays. A multi-page
    /// TIFF or PDF has no delays, so it is not an animation.
    private func animation() -> AnimationMetadata? {
        let capacity = 4096
        var delays = [Int32](repeating: 0, count: capacity)
        let count = Int(swift_vips_image_get_int_array_field(pointer, "delay", &delays, Int32(capacity)))
        guard count >= 0 else { return nil }
        return AnimationMetadata(
            loopCount: metadataInt("loop") ?? 0,
            frameDelays: delays.prefix(min(count, capacity)).map { .milliseconds(Int($0)) }
        )
    }

    // MARK: - Native → Hokusai mappings

    /// The loader operation without its input-kind suffix. Matching is by exact
    /// suffix, never by substring, so a name can only map to what it names.
    static func loaderBase(_ loader: String?) -> String? {
        guard var name = loader else { return nil }
        for suffix in ["_source", "_buffer"] where name.hasSuffix(suffix) {
            name.removeLast(suffix.count)
        }
        return name
    }

    /// The format a loader produced, or `nil` for loaders Hokusai does not name.
    ///
    /// libvips decodes AVIF and HEIC with one `heifload`, so the container's
    /// compression decides between them.
    static func sourceFormat(loader: String?, heifCompression: String?) -> ImageFormat? {
        switch loaderBase(loader) {
        case "jpegload": .jpeg
        case "pngload": .png
        case "webpload": .webp
        case "gifload": .gif
        case "tiffload": .tiff
        case "svgload": .svg
        case "pdfload": .pdf
        case "heifload": heifCompression == "av1" ? .avif : .heif
        default: nil
        }
    }

    static func interpretation(_ value: Int) -> PixelInterpretation {
        switch Int32(value) {
        case Int32(VIPS_INTERPRETATION_B_W.rawValue), Int32(VIPS_INTERPRETATION_GREY16.rawValue): .grayscale
        case Int32(VIPS_INTERPRETATION_sRGB.rawValue): .sRGB
        case Int32(VIPS_INTERPRETATION_RGB.rawValue), Int32(VIPS_INTERPRETATION_RGB16.rawValue): .rgb
        case Int32(VIPS_INTERPRETATION_CMYK.rawValue): .cmyk
        case Int32(VIPS_INTERPRETATION_LAB.rawValue), Int32(VIPS_INTERPRETATION_LABQ.rawValue), Int32(VIPS_INTERPRETATION_LABS.rawValue): .lab
        case Int32(VIPS_INTERPRETATION_LCH.rawValue): .lch
        case Int32(VIPS_INTERPRETATION_XYZ.rawValue): .xyz
        case Int32(VIPS_INTERPRETATION_HSV.rawValue): .hsv
        case Int32(VIPS_INTERPRETATION_scRGB.rawValue): .scRGB
        case Int32(VIPS_INTERPRETATION_MULTIBAND.rawValue): .multiband
        default: .unknown
        }
    }

    static func sampleFormat(_ value: Int) -> PixelSampleFormat {
        switch Int32(value) {
        case Int32(VIPS_FORMAT_UCHAR.rawValue): .uint8
        case Int32(VIPS_FORMAT_CHAR.rawValue): .int8
        case Int32(VIPS_FORMAT_USHORT.rawValue): .uint16
        case Int32(VIPS_FORMAT_SHORT.rawValue): .int16
        case Int32(VIPS_FORMAT_UINT.rawValue): .uint32
        case Int32(VIPS_FORMAT_INT.rawValue): .int32
        case Int32(VIPS_FORMAT_FLOAT.rawValue): .float32
        case Int32(VIPS_FORMAT_DOUBLE.rawValue): .float64
        case Int32(VIPS_FORMAT_COMPLEX.rawValue), Int32(VIPS_FORMAT_DPCOMPLEX.rawValue): .complex
        default: .unknown
        }
    }

    /// libvips stores resolution in pixels per millimetre and reports exactly 1
    /// for an image that recorded none, which is treated as "no density".
    static func density(xres: Double, yres: Double) -> ImageDensity? {
        guard xres > 0, yres > 0, !(xres == 1 && yres == 1) else { return nil }
        return ImageDensity(horizontal: xres * 25.4, vertical: yres * 25.4)
    }

    static func resolutionUnit(_ value: String?) -> ResolutionUnit? {
        switch value {
        case "in": .inch
        case "cm": .centimetre
        default: nil
        }
    }
}
