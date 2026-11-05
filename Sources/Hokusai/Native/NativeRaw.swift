import Foundation
import CVips

extension RawPixelFormat {
    fileprivate var bandFormat: VipsBandFormat { bytesPerChannel == 1 ? VIPS_FORMAT_UCHAR : VIPS_FORMAT_USHORT }

    /// The colour model libvips needs to scale and convert this layout correctly.
    fileprivate var interpretation: VipsInterpretation {
        switch (isGray, bytesPerChannel) {
        case (true, 1): VIPS_INTERPRETATION_B_W
        case (true, _): VIPS_INTERPRETATION_GREY16
        case (false, 1): VIPS_INTERPRETATION_sRGB
        case (false, _): VIPS_INTERPRETATION_RGB16
        }
    }
}

// MARK: - Raw source

extension NativeImage {
    /// Copies caller pixels into native ownership and tags them with their colour model.
    ///
    /// A padded row stride is removed first, so libvips always sees a tightly
    /// packed buffer. The bytes are copied before this returns, so nothing
    /// borrows `Data` storage during lazy evaluation. Premultiplied input is
    /// divided out so later operations see straight alpha.
    static func open(raw source: RawSource) throws -> NativeImage {
        try VipsRuntime.ensureInitialized()
        let format = source.format
        let rowBytes = source.width * format.bytesPerPixel

        func make(from bytes: UnsafeRawBufferPointer) throws -> NativeImage {
            try producing({ output in
                guard let image = swift_vips_new_from_memory(
                    bytes.baseAddress, bytes.count, Int32(source.width), Int32(source.height), Int32(format.channels),
                    Int32(format.bandFormat.rawValue), Int32(format.interpretation.rawValue)
                ) else { return -1 }
                output.pointee = image
                return 0
            }, failure: { .decode(.native("load raw pixels", "could not create an image from the raw pixels")) })
        }

        var image: NativeImage
        if source.rowStride == rowBytes {
            image = try source.data.withUnsafeBytes { try make(from: $0) }
        } else {
            var packed = Data(count: rowBytes * source.height)
            packed.withUnsafeMutableBytes { destination in
                source.data.withUnsafeBytes { input in
                    for row in 0..<source.height {
                        let from = input.baseAddress! + row * source.rowStride
                        memcpy(destination.baseAddress! + row * rowBytes, from, rowBytes)
                    }
                }
            }
            image = try packed.withUnsafeBytes { try make(from: $0) }
        }
        if source.premultiplied && format.hasAlpha {
            // Dividing out alpha yields float; return to the sample type the caller gave.
            image = try image.applying("load raw pixels") { swift_vips_unpremultiply($0, $1) }
                .castRounded(to: Int32(format.bandFormat.rawValue), operation: "load raw pixels")
        }
        return image
    }
}

// MARK: - Raw sink

extension NativeImage {
    /// Converts to the colour model, alpha and sample width of `format`.
    ///
    /// Colour conversion goes first because it is what rescales 8 and 16 bits
    /// (a plain cast would clip); the cast afterwards only fixes the sample
    /// type of an image libvips left as float or double.
    func converted(to format: RawPixelFormat, premultiplied: Bool, background rgba: [Double]) throws -> NativeImage {
        var image = self
        let target = format.interpretation
        if swift_vips_image_get_interpretation(image.pointer) != target.rawValue || image.bandFormat != Int32(format.bandFormat.rawValue) {
            image = try image.applying("convert to raw") { swift_vips_colourspace($0, $1, target) }
        }
        if format.hasAlpha {
            image = try image.ensureAlpha(opacity: 1)
        } else {
            image = try image.flatten(background: rgba)
        }
        // Premultiply while the samples still have their range, then fix the sample type
        // (premultiplying yields float).
        if premultiplied && format.hasAlpha {
            image = try image.applying("premultiply raw") { swift_vips_premultiply($0, $1) }
        }
        if image.bandFormat != Int32(format.bandFormat.rawValue) {
            image = try image.castRounded(to: Int32(format.bandFormat.rawValue), operation: "convert to raw")
        }
        if swift_vips_image_get_interpretation(image.pointer) != target.rawValue {
            image = try image.applying("convert to raw") { swift_vips_set_interpretation($0, $1, Int32(target.rawValue)) }
        }
        guard image.bands == format.channels else {
            throw HokusaiError.transform(.native("convert to raw", "expected \(format.channels) channels but the image has \(image.bands)"))
        }
        return image
    }

    /// Evaluates the image into one owned buffer of tightly packed samples.
    func pixelBytes() throws -> Data {
        var size = 0
        guard let buffer = swift_vips_write_to_memory(pointer, &size) else {
            throw HokusaiError.nativeEncode("raw")
        }
        defer { swift_vips_g_free(buffer) }
        return Data(bytes: buffer, count: size)
    }
}
