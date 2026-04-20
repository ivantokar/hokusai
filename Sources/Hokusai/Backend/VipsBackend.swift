import Foundation
import CVips

/// libvips backend implementation for high-performance image operations
final class VipsBackend: ImageBackend {
    private var imagePointer: UnsafeMutablePointer<CVips.VipsImage>?
    private let lock = NSLock()

    /// Initialize libvips (call once at app startup)
    static func initialize() throws {
        let result = vips_init("Hokusai")
        guard result == 0 else {
            throw HokusaiError.initializationFailed("vips_init returned \(result)")
        }
    }

    /// Shutdown libvips (call at app teardown)
    static func shutdown() {
        vips_shutdown()
    }

    /// Internal initializer with vips image pointer
    init(takingOwnership pointer: UnsafeMutablePointer<CVips.VipsImage>) {
        self.imagePointer = pointer
    }

    deinit {
        lock.lock()
        defer { lock.unlock() }

        if let pointer = imagePointer {
            g_object_unref(pointer)
            imagePointer = nil
        }
    }

    /// Get the underlying pointer (for internal use)
    func getPointer() throws -> UnsafeMutablePointer<CVips.VipsImage> {
        lock.lock()
        defer { lock.unlock() }

        guard let pointer = imagePointer else {
            throw HokusaiError.invalidOperation("Image has been deallocated")
        }
        return pointer
    }

    // MARK: - ImageBackend Protocol Implementation

    static func loadFromFile(_ path: String) throws -> VipsBackend {
        guard FileManager.default.fileExists(atPath: path) else {
            throw HokusaiError.fileNotFound(path)
        }

        let output = swift_vips_image_new_from_file(path)
        guard let img = output else {
            throw HokusaiError.loadFailed(getLastError())
        }

        return VipsBackend(takingOwnership: img)
    }

    static func loadFromBuffer(_ data: Data) throws -> VipsBackend {
        guard !data.isEmpty else {
            throw HokusaiError.invalidImageData
        }

        let output = data.withUnsafeBytes { bytes in
            swift_vips_image_new_from_buffer(bytes.baseAddress, data.count)
        }

        guard let img = output else {
            throw HokusaiError.loadFailed(getLastError())
        }

        return VipsBackend(takingOwnership: img)
    }

    func saveToFile(_ path: String, format: String?, quality: Int?) throws {
        let pointer = try getPointer()
        let detectedFormat = format ?? detectFormat(from: path)

        let result: Int32
        switch detectedFormat.lowercased() {
        case "jpeg", "jpg":
            result = swift_vips_jpegsave(pointer, path, Int32(quality ?? 85), 0, 1)
        case "png":
            result = swift_vips_pngsave(pointer, path, Int32(quality ?? 6), 0)
        case "webp":
            result = swift_vips_webpsave(pointer, path, Int32(quality ?? 80), 0, 4)
        case "avif", "heif", "heic":
            result = swift_vips_heifsave(pointer, path, Int32(quality ?? 80), 0, 4)
        case "tiff", "tif":
            result = swift_vips_tiffsave(pointer, path, 0)
        case "gif":
            result = swift_vips_gifsave(pointer, path)
        default:
            throw HokusaiError.unsupportedFormat(detectedFormat)
        }

        guard result == 0 else {
            throw HokusaiError.saveFailed(Self.getLastError())
        }
    }

    func toBuffer(format: String?, quality: Int?) throws -> Data {
        let pointer = try getPointer()
        let targetFormat = format ?? "jpeg"

        var buffer: UnsafeMutableRawPointer?
        var length: Int = 0

        let result: Int32
        switch targetFormat.lowercased() {
        case "jpeg", "jpg":
            result = swift_vips_jpegsave_buffer(pointer, &buffer, &length, Int32(quality ?? 85))
        case "png":
            result = swift_vips_pngsave_buffer(pointer, &buffer, &length, Int32(quality ?? 6))
        case "webp":
            result = swift_vips_webpsave_buffer(pointer, &buffer, &length, Int32(quality ?? 80), 0)
        case "avif", "heif", "heic":
            result = swift_vips_heifsave_buffer(pointer, &buffer, &length, Int32(quality ?? 80))
        case "tiff", "tif":
            result = swift_vips_tiffsave_buffer(pointer, &buffer, &length)
        case "gif":
            result = swift_vips_gifsave_buffer(pointer, &buffer, &length)
        default:
            throw HokusaiError.unsupportedFormat(targetFormat)
        }

        guard result == 0, let buf = buffer else {
            throw HokusaiError.saveFailed(Self.getLastError())
        }

        defer { g_free(buffer) }
        return Data(bytes: buf, count: length)
    }

    func getWidth() throws -> Int {
        let pointer = try getPointer()
        return Int(vips_image_get_width(pointer))
    }

    func getHeight() throws -> Int {
        let pointer = try getPointer()
        return Int(vips_image_get_height(pointer))
    }

    func getBands() throws -> Int {
        let pointer = try getPointer()
        return Int(vips_image_get_bands(pointer))
    }

    func hasAlpha() throws -> Bool {
        let pointer = try getPointer()
        return vips_image_hasalpha(pointer) != 0
    }

    func extendedMetadata() throws -> [String: String] {
        let pointer = try getPointer()
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

        // Add convenient normalized aliases for frequent UI/API consumers.
        metadata["width"] = metadata["width"] ?? String(Int(vips_image_get_width(pointer)))
        metadata["height"] = metadata["height"] ?? String(Int(vips_image_get_height(pointer)))
        metadata["bands"] = metadata["bands"] ?? String(Int(vips_image_get_bands(pointer)))
        metadata["hasAlpha"] = metadata["hasAlpha"] ?? String(vips_image_hasalpha(pointer) != 0)

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

    // MARK: - Helper Methods

    private func detectFormat(from path: String) -> String {
        let ext = (path as NSString).pathExtension
        return ext.isEmpty ? "jpeg" : ext
    }

    static func getLastError() -> String {
        guard let buffer = vips_error_buffer() else {
            return "Unknown vips error"
        }
        vips_error_clear()
        return String(cString: buffer)
    }

    /// Get libvips version
    static var version: String {
        guard let versionStr = vips_version_string() else {
            return "unknown"
        }
        return String(cString: versionStr)
    }
}
