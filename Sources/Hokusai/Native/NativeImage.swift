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
    /// On failure any partial output is released and `failure` builds the
    /// error for the boundary that called it.
    static func producing(
        _ body: (UnsafeMutablePointer<Pointer?>) -> Int32,
        failure: () -> HokusaiError
    ) throws -> NativeImage {
        var output: Pointer?
        guard body(&output) == 0, let output else {
            VipsBackend.discardPartialImage(output)
            throw failure()
        }
        return NativeImage(takingOwnership: output)
    }

    /// Applies a single-input native transform named `operation`.
    func applying(
        _ operation: String,
        _ body: (Pointer, UnsafeMutablePointer<Pointer?>) -> Int32
    ) throws -> NativeImage {
        try Self.producing({ body(pointer, $0) }, failure: { .nativeTransform(operation) })
    }
}

// MARK: - Sources

extension NativeImage {
    /// Opens a local source lazily under `options`.
    ///
    /// Opening reads only the header; pixels are decoded when first needed.
    /// Fails with `io(.read)` for a missing or unreadable file, `resource` when
    /// a limit is exceeded, and `decode` when libvips cannot open the file.
    static func open(path: String, options: InputOptions = InputOptions()) throws -> NativeImage {
        try VipsRuntime.ensureInitialized()
        try requireReadableFile(path)
        if let size = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey]).fileSize {
            try options.limits.checkEncodedBytes(size)
        }

        let name = URL(fileURLWithPath: path).lastPathComponent
        return try opened(options: options, operation: "decode \(name)", reason: "could not decode the image file") { page in
            swift_vips_open_file(path, options.access == .sequential ? 1 : 0, options.failOn.vipsValue, page, options.revalidate ? 1 : 0)
        }
    }

    /// Copies encoded bytes into native ownership and opens them lazily under `options`.
    ///
    /// The bytes are copied into libvips-owned storage before this returns, so
    /// lazy evaluation never borrows `Data` storage.
    static func open(data: Data, options: InputOptions = InputOptions()) throws -> NativeImage {
        try VipsRuntime.ensureInitialized()

        guard !data.isEmpty else {
            throw HokusaiError.invalidInput(reason: "encoded data is empty")
        }
        try options.limits.checkEncodedBytes(data.count)

        return try opened(options: options, operation: "decode input data", reason: "could not decode the image data") { page in
            data.withUnsafeBytes { bytes in
                swift_vips_open_buffer(bytes.baseAddress, data.count, options.access == .sequential ? 1 : 0, options.failOn.vipsValue, page)
            }
        }
    }

    /// Opens a source, applies page selection, and enforces decoded-size limits.
    ///
    /// `open` receives a page index, or -1 for "no page argument" (loaders
    /// without pages reject the argument). Page selection is validated against
    /// the page count libvips reports rather than by reading error text.
    private static func opened(
        options: InputOptions,
        operation: String,
        reason: String,
        _ open: (Int32) -> Pointer?
    ) throws -> NativeImage {
        func attempt(page: Int32) throws -> NativeImage {
            guard let pointer = open(page) else {
                throw HokusaiError.decode(.native(operation, reason))
            }
            return NativeImage(takingOwnership: pointer)
        }

        var image = try attempt(page: -1)
        if let page = options.page {
            let pages = image.pageCount
            guard page < pages else {
                if pages == 1 {
                    throw HokusaiError.unsupported(feature: "page selection", reason: "this image has a single page")
                }
                throw HokusaiError.invalidOption(name: "page", reason: "page \(page) is out of range; the image has \(pages) pages")
            }
            if page > 0 {
                image = try attempt(page: Int32(page))
            }
        }
        try options.limits.checkDecoded(width: image.width, height: image.height, channels: image.bands)
        return image
    }

    /// The number of pages libvips reports; 1 for single-page formats.
    var pageCount: Int { Int(swift_vips_image_n_pages(pointer)) }

    /// Wraps this freshly opened source so a failure to produce its pixels can
    /// be told apart from failures in later operations. See
    /// `swift_vips_source_probe_image`.
    func probingSource() throws -> NativeImage {
        try Self.producing({ output in
            guard let wrapped = swift_vips_source_probe_image(pointer) else { return -1 }
            output.pointee = wrapped
            return 0
        }, failure: { .runtime(.native("prepare source", "could not wrap the source for evaluation")) })
    }

    /// Whether this probe-wrapped source failed to produce pixels.
    var sourceProbeFailed: Bool { swift_vips_source_probe_failed(pointer) != 0 }

    /// Opens a local source through libvips' shrink-on-load thumbnail path.
    static func thumbnail(path: String, width: Int, options: ThumbnailOptions) throws -> NativeImage {
        try VipsRuntime.ensureInitialized()
        let arguments = try ThumbnailArguments.validate(width: width, options: options)

        try requireReadableFile(path)

        return try producing({
            swift_vips_thumbnail(path, $0, arguments.width, arguments.height, arguments.crop, arguments.noRotate)
        }, failure: { .decode(.native("thumbnail \(URL(fileURLWithPath: path).lastPathComponent)", "could not decode and resize the image file")) })
    }

    /// Creates a shrink-on-load thumbnail from copied encoded bytes.
    static func thumbnail(data: Data, width: Int, options: ThumbnailOptions) throws -> NativeImage {
        try VipsRuntime.ensureInitialized()
        let arguments = try ThumbnailArguments.validate(width: width, options: options)

        guard !data.isEmpty else {
            throw HokusaiError.invalidInput(reason: "encoded data is empty")
        }

        // As with normal buffer loading, the shim copies bytes before lazy
        // thumbnail evaluation can outlive the Swift `Data` value.
        return try producing({ output in
            data.withUnsafeBytes { bytes in
                swift_vips_thumbnail_buffer(
                    bytes.baseAddress, data.count, output,
                    arguments.width, arguments.height, arguments.crop, arguments.noRotate)
            }
        }, failure: { .decode(.native("thumbnail input data", "could not decode and resize the image data")) })
    }

    /// Classifies a missing source as I/O before libvips reports it as a
    /// generic load failure.
    private static func requireReadableFile(_ path: String) throws {
        guard FileManager.default.isReadableFile(atPath: path) else {
            let exists = FileManager.default.fileExists(atPath: path)
            throw HokusaiError.io(url: URL(fileURLWithPath: path), operation: .read, reason: exists ? "file is not readable" : "file not found")
        }
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
}

extension DecodeFailureLevel {
    /// The matching `VipsFailOn` value.
    var vipsValue: Int32 {
        switch self {
        case .none: Int32(VIPS_FAIL_ON_NONE.rawValue)
        case .truncated: Int32(VIPS_FAIL_ON_TRUNCATED.rawValue)
        case .error: Int32(VIPS_FAIL_ON_ERROR.rawValue)
        case .warning: Int32(VIPS_FAIL_ON_WARNING.rawValue)
        }
    }
}
