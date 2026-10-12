import Foundation
import CVips

/// Owns one libvips image reference for its whole lifetime.
///
/// This is Hokusai's single native ownership type: the reference is released
/// exactly once in `deinit`, and every operation returns a new `NativeImage`
/// rather than mutating the receiver. libvips images are immutable once built
/// and safe to read from multiple threads, so an instance may back a shared
/// legacy handle as well as a graph built inside one terminal evaluation.
final class NativeImage {
    typealias Pointer = UnsafeMutablePointer<CVips.VipsImage>

    let pointer: Pointer

    /// Takes ownership of a valid, owned libvips image reference.
    init(takingOwnership pointer: Pointer) {
        self.pointer = pointer
    }

    deinit {
        g_object_unref(pointer)
    }

    /// The image width in pixels.
    var width: Int { Int(vips_image_get_width(pointer)) }

    /// The image height in pixels.
    var height: Int { Int(vips_image_get_height(pointer)) }

    /// The number of bands (channels).
    var bands: Int { Int(vips_image_get_bands(pointer)) }

    /// Whether libvips considers the image to carry an alpha band.
    var hasAlpha: Bool { vips_image_hasalpha(pointer) != 0 }

    /// Runs a native call that produces one owned output image.
    ///
    /// On failure any partial output is released and the libvips diagnostic is
    /// passed to `failure` so callers keep their existing error categories.
    static func producing(
        _ body: (UnsafeMutablePointer<Pointer?>) -> Int32,
        failure: (String) -> HokusaiError
    ) throws -> NativeImage {
        var output: Pointer?
        guard body(&output) == 0, let output else {
            VipsBackend.discardPartialImage(output)
            throw failure(VipsBackend.getLastError())
        }
        return NativeImage(takingOwnership: output)
    }

    /// Applies a single-input native operation to this image.
    func applying(
        _ body: (Pointer, UnsafeMutablePointer<Pointer?>) -> Int32,
        failure: (String) -> HokusaiError = HokusaiError.vipsError
    ) throws -> NativeImage {
        try Self.producing({ body(pointer, $0) }, failure: failure)
    }
}

// MARK: - Sources

extension NativeImage {
    /// Opens a local source lazily with libvips' requested access pattern.
    static func open(path: String, options: LoadOptions = LoadOptions()) throws -> NativeImage {
        try VipsRuntime.ensureInitialized()

        guard FileManager.default.fileExists(atPath: path) else {
            throw HokusaiError.fileNotFound(path)
        }

        let output: Pointer?
        switch options.access {
        case .sequential:
            output = swift_vips_image_new_from_file_sequential(path)
        case .random:
            output = swift_vips_image_new_from_file(path)
        }

        guard let img = output else {
            throw HokusaiError.loadFailed("\(path): \(VipsBackend.getLastError())")
        }
        return NativeImage(takingOwnership: img)
    }

    /// Copies encoded bytes into native ownership and opens them lazily.
    static func open(data: Data, options: LoadOptions = LoadOptions()) throws -> NativeImage {
        try VipsRuntime.ensureInitialized()

        guard !data.isEmpty else {
            throw HokusaiError.invalidImageData
        }

        // The shim copies bytes into libvips-owned storage before this closure
        // returns, so lazy evaluation never borrows `Data` storage.
        let output: Pointer? = data.withUnsafeBytes { bytes in
            switch options.access {
            case .sequential:
                return swift_vips_image_new_from_buffer_sequential(bytes.baseAddress, data.count)
            case .random:
                return swift_vips_image_new_from_buffer(bytes.baseAddress, data.count)
            }
        }

        guard let img = output else {
            throw HokusaiError.loadFailed(VipsBackend.getLastError())
        }
        return NativeImage(takingOwnership: img)
    }

    /// Opens a local source through libvips' shrink-on-load thumbnail path.
    static func thumbnail(path: String, width: Int, options: ThumbnailOptions) throws -> NativeImage {
        try VipsRuntime.ensureInitialized()
        let arguments = try ThumbnailArguments.validate(width: width, options: options)

        guard FileManager.default.fileExists(atPath: path) else {
            throw HokusaiError.fileNotFound(path)
        }

        return try producing({
            swift_vips_thumbnail(path, $0, arguments.width, arguments.height, arguments.crop, arguments.noRotate)
        }, failure: { HokusaiError.loadFailed("thumbnail of \(path): \($0)") })
    }

    /// Creates a shrink-on-load thumbnail from copied encoded bytes.
    static func thumbnail(data: Data, width: Int, options: ThumbnailOptions) throws -> NativeImage {
        try VipsRuntime.ensureInitialized()
        let arguments = try ThumbnailArguments.validate(width: width, options: options)

        guard !data.isEmpty else {
            throw HokusaiError.invalidImageData
        }

        // As with normal buffer loading, the shim copies bytes before lazy
        // thumbnail evaluation can outlive the Swift `Data` value.
        return try producing({ output in
            data.withUnsafeBytes { bytes in
                swift_vips_thumbnail_buffer(
                    bytes.baseAddress, data.count, output,
                    arguments.width, arguments.height, arguments.crop, arguments.noRotate)
            }
        }, failure: { HokusaiError.loadFailed("thumbnail from buffer: \($0)") })
    }
}

// MARK: - Metadata

extension NativeImage {
    /// Copies scalar libvips fields and adds stable aliases used by Hokusai.
    func extendedMetadata() -> [String: String] {
        var metadata: [String: String] = [:]

        if let fields = swift_vips_image_get_fields(pointer) {
            defer { swift_vips_g_strfreev(fields) }

            var index = 0
            while let fieldPointer = fields[index] {
                let field = String(cString: fieldPointer)
                if let valuePointer = swift_vips_image_get_as_string(pointer, field) {
                    metadata[field] = String(cString: valuePointer)
                    swift_vips_g_free(valuePointer)
                }
                index += 1
            }
        }

        // Add stable aliases where libvips exposes a native enum or resolution
        // only through its lower-level metadata dictionary.
        metadata["width"] = metadata["width"] ?? String(width)
        metadata["height"] = metadata["height"] ?? String(height)
        metadata["bands"] = metadata["bands"] ?? String(bands)
        metadata["hasAlpha"] = metadata["hasAlpha"] ?? String(hasAlpha)

        let interpretation = swift_vips_image_get_interpretation(pointer)
        metadata["interpretation"] = metadata["interpretation"] ?? String(interpretation)
        if metadata["interpretationNick"] == nil, let nick = swift_vips_interpretation_nick(interpretation) {
            metadata["interpretationNick"] = String(cString: nick)
        }

        let bandFormat = swift_vips_image_get_band_format(pointer)
        metadata["bandFormat"] = metadata["bandFormat"] ?? String(bandFormat)
        if metadata["bandFormatNick"] == nil, let nick = swift_vips_band_format_nick(bandFormat) {
            metadata["bandFormatNick"] = String(cString: nick)
        }

        let coding = swift_vips_image_get_coding(pointer)
        metadata["coding"] = metadata["coding"] ?? String(coding)
        if metadata["codingNick"] == nil, let nick = swift_vips_coding_nick(coding) {
            metadata["codingNick"] = String(cString: nick)
        }

        let xres = swift_vips_image_get_xres(pointer)
        let yres = swift_vips_image_get_yres(pointer)
        metadata["xres"] = metadata["xres"] ?? String(xres)
        metadata["yres"] = metadata["yres"] ?? String(yres)
        metadata["xresDpi"] = metadata["xresDpi"] ?? String(xres * 25.4)
        metadata["yresDpi"] = metadata["yresDpi"] ?? String(yres * 25.4)

        return metadata
    }

    /// Copies an optional binary libvips metadata field into Swift data.
    func metadataBlob(named name: String) -> Data? {
        var length = 0
        guard let copied = swift_vips_image_get_blob_copy(pointer, name, &length) else {
            return nil
        }
        defer { g_free(copied) }
        return Data(bytes: copied, count: length)
    }

    /// Returns normalized metadata available from this image.
    ///
    /// Optional fields remain `nil` when the loader did not expose them. This
    /// may inspect headers but does not encode an output image.
    func metadata() -> ImageMetadata {
        let metadata = extendedMetadata()
        let format = metadata["vips-loader"].flatMap { loader in
            ImageFormat.from(fileExtension: loader.replacingOccurrences(of: "load", with: ""))
        }
        return ImageMetadata(
            width: width,
            height: height,
            channels: bands,
            format: format,
            space: metadata["interpretationNick"],
            hasAlpha: hasAlpha,
            orientation: metadata["orientation"].flatMap(Int.init),
            density: metadata["xresDpi"].flatMap(Double.init),
            pages: metadata["n-pages"].flatMap(Int.init),
            size: metadata["sizeof_header"].flatMap(Int.init),
            colorSpace: Self.colorSpace(from: metadata["interpretationNick"]),
            densityXY: Self.density(from: metadata),
            pageHeight: metadata["page-height"].flatMap(Int.init),
            isAnimated: (metadata["n-pages"].flatMap(Int.init) ?? 1) > 1,
            exif: metadataBlob(named: "exif-data"),
            iccProfile: metadataBlob(named: "icc-profile-data"),
            xmp: metadataBlob(named: "xmp-data")
        )
    }

    /// Normalizes recognised libvips interpretation names to the public enum.
    private static func colorSpace(from interpretation: String?) -> ColorSpace? {
        switch interpretation?.lowercased() {
        case "srgb", "rgb16": .sRGB
        case "b-w", "grey16": .grayscale
        default: nil
        }
    }

    /// Builds a density value only when both libvips resolutions are present.
    private static func density(from metadata: [String: String]) -> ImageDensity? {
        guard let horizontal = metadata["xresDpi"].flatMap(Double.init),
              let vertical = metadata["yresDpi"].flatMap(Double.init) else {
            return nil
        }
        return ImageDensity(horizontal: horizontal, vertical: vertical)
    }
}
