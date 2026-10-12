import Foundation
import CVips

/// Legacy backend facade over a ``NativeImage``.
///
/// Native ownership lives in `NativeImage`; this type only adapts it to the
/// legacy `ImageBackend` string-based encoder surface until #32 removes it.
/// Process-wide initialization belongs to `VipsRuntime`.
final class VipsBackend: ImageBackend {
    let native: NativeImage

    init(native: NativeImage) {
        self.native = native
    }

    /// Takes ownership of a valid, owned libvips image pointer.
    convenience init(takingOwnership pointer: UnsafeMutablePointer<CVips.VipsImage>) {
        self.init(native: NativeImage(takingOwnership: pointer))
    }

    /// Returns the native pointer, valid for this backend's lifetime.
    func getPointer() throws -> UnsafeMutablePointer<CVips.VipsImage> {
        native.pointer
    }

    // MARK: - ImageBackend Protocol Implementation

    static func loadFromFile(_ path: String, options: LoadOptions = LoadOptions()) throws -> VipsBackend {
        VipsBackend(native: try NativeImage.open(path: path, options: options))
    }

    static func loadFromBuffer(_ data: Data, options: LoadOptions = LoadOptions()) throws -> VipsBackend {
        VipsBackend(native: try NativeImage.open(data: data, options: options))
    }

    static func thumbnailFromFile(_ path: String, width: Int, options: ThumbnailOptions) throws -> VipsBackend {
        VipsBackend(native: try NativeImage.thumbnail(path: path, width: width, options: options))
    }

    static func thumbnailFromBuffer(_ data: Data, width: Int, options: ThumbnailOptions) throws -> VipsBackend {
        VipsBackend(native: try NativeImage.thumbnail(data: data, width: width, options: options))
    }

    /// Selects a legacy encoder and writes the evaluated image to a local path.
    func saveToFile(_ path: String, format: String?, quality: Int?) throws {
        let pointer = try getPointer()
        let detectedFormat = format ?? detectFormat(from: path)

        let result: Int32
        switch detectedFormat.lowercased() {
        case "jpeg", "jpg":
            result = swift_vips_jpegsave(pointer, path, Int32(quality ?? 85), 0, 1)
        case "png":
            result = swift_vips_pngsave(pointer, path, Int32(quality ?? 6), 0, 1)
        case "webp":
            result = swift_vips_webpsave(pointer, path, Int32(quality ?? 80), 0, 4, 1)
        case "avif":
            result = swift_vips_heifsave(pointer, path, Int32(quality ?? 80), 0, 4, 1, 1)
        case "heif", "heic":
            result = swift_vips_heifsave(pointer, path, Int32(quality ?? 80), 0, 4, 1, 0)
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

    /// Selects a legacy encoder and returns its bytes in Swift-owned storage.
    func toBuffer(format: String?, quality: Int?) throws -> Data {
        let pointer = try getPointer()
        let targetFormat = format ?? "jpeg"

        var buffer: UnsafeMutableRawPointer?
        var length: Int = 0

        let result: Int32
        switch targetFormat.lowercased() {
        case "jpeg", "jpg":
            result = swift_vips_jpegsave_buffer(pointer, &buffer, &length, Int32(quality ?? 85), 1)
        case "png":
            result = swift_vips_pngsave_buffer(pointer, &buffer, &length, Int32(quality ?? 6), 1)
        case "webp":
            result = swift_vips_webpsave_buffer(pointer, &buffer, &length, Int32(quality ?? 80), 0, 4, 1)
        case "avif":
            result = swift_vips_heifsave_buffer(pointer, &buffer, &length, Int32(quality ?? 80), 0, 4, 1, 1)
        case "heif", "heic":
            result = swift_vips_heifsave_buffer(pointer, &buffer, &length, Int32(quality ?? 80), 0, 4, 1, 0)
        case "tiff", "tif":
            result = swift_vips_tiffsave_buffer(pointer, &buffer, &length)
        case "gif":
            result = swift_vips_gifsave_buffer(pointer, &buffer, &length)
        default:
            throw HokusaiError.unsupportedFormat(targetFormat)
        }

        guard result == 0, let buf = buffer else {
            if let buffer { g_free(buffer) }
            throw HokusaiError.saveFailed(Self.getLastError())
        }

        defer { g_free(buffer) }
        return Data(bytes: buf, count: length)
    }

    func getWidth() throws -> Int { native.width }

    func getHeight() throws -> Int { native.height }

    func getBands() throws -> Int { native.bands }

    func hasAlpha() throws -> Bool { native.hasAlpha }

    // MARK: - Helper Methods

    /// Uses a filename extension, retaining JPEG as the legacy no-extension default.
    private func detectFormat(from path: String) -> String {
        let ext = (path as NSString).pathExtension
        return ext.isEmpty ? "jpeg" : ext
    }

    /// Releases a native image returned alongside a failed operation. libvips
    /// normally leaves output null on failure, but adapters must not assume it.
    static func discardPartialImage(_ image: UnsafeMutablePointer<CVips.VipsImage>?) {
        if let image { g_object_unref(image) }
    }

    /// Copies and clears libvips' process-global error buffer.
    ///
    /// The buffer is shared by every thread, so under concurrent failures the
    /// text may include diagnostics from other evaluations. Treat it as detail;
    /// the typed Hokusai operation and category identify the failure.
    static func getLastError() -> String {
        guard let buffer = swift_vips_error_copy() else {
            return "Unknown vips error"
        }
        defer { g_free(buffer) }
        let message = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "Unknown vips error" : message
    }

    /// The linked libvips version string.
    static var version: String {
        guard let versionStr = vips_version_string() else {
            return "unknown"
        }
        return String(cString: versionStr)
    }
}
