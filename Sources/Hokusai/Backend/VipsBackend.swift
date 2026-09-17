import Foundation
import CVips

/// Owns one libvips image pointer and centralizes native decode and encode work.
///
/// `VipsBackend` is the ownership boundary between Swift and libvips. It
/// serializes access to its pointer, releases it exactly once in `deinit`, and
/// keeps process-wide runtime state behind a separate lock.
final class VipsBackend: ImageBackend {
    private var imagePointer: UnsafeMutablePointer<CVips.VipsImage>?
    private let lock = NSLock()

    // MARK: - Runtime Lifecycle

    private enum RuntimeState {
        case uninitialized
        case initialized
        case shutdownCompleted
    }

    /// Process-global libvips state. Only read or written while holding
    /// `runtimeLock`, which makes the `nonisolated(unsafe)` sound.
    nonisolated(unsafe) private static var runtimeState: RuntimeState = .uninitialized
    nonisolated(unsafe) private static var liveImageCount = 0
    private static let runtimeLock = NSLock()

    /// Initializes the process-wide libvips runtime once.
    ///
    /// Loading entry points call this automatically. Repeated and concurrent
    /// calls are safe. A successful final shutdown is irreversible because
    /// libvips cannot be reinitialized in the same process.
    static func initialize() throws {
        runtimeLock.lock()
        defer { runtimeLock.unlock() }

        switch runtimeState {
        case .initialized:
            return
        case .shutdownCompleted:
            throw HokusaiError.initializationFailed(
                "libvips cannot be re-initialized after shutdown(); shutdown() is a final process-teardown operation")
        case .uninitialized:
            guard vips_init("Hokusai") == 0 else {
                throw HokusaiError.initializationFailed(getLastError())
            }
            runtimeState = .initialized
        }
    }

    /// Performs final process teardown after every image handle has been released.
    static func shutdown() throws {
        runtimeLock.lock()
        defer { runtimeLock.unlock() }

        guard runtimeState == .initialized else { return }
        guard liveImageCount == 0 else {
            throw HokusaiError.invalidOperation(
                "Cannot shut down libvips while \(liveImageCount) Hokusai image handle(s) are still alive")
        }
        vips_shutdown()
        runtimeState = .shutdownCompleted
    }

    /// Takes ownership of a valid, owned libvips image pointer.
    init(takingOwnership pointer: UnsafeMutablePointer<CVips.VipsImage>) {
        self.imagePointer = pointer
        Self.runtimeLock.lock()
        Self.liveImageCount += 1
        Self.runtimeLock.unlock()
    }

    deinit {
        lock.lock()
        defer { lock.unlock() }

        if let pointer = imagePointer {
            g_object_unref(pointer)
            imagePointer = nil
            Self.runtimeLock.lock()
            Self.liveImageCount -= 1
            Self.runtimeLock.unlock()
        }
    }

    /// Returns the live native pointer or throws if it was already released.
    func getPointer() throws -> UnsafeMutablePointer<CVips.VipsImage> {
        lock.lock()
        defer { lock.unlock() }

        guard let pointer = imagePointer else {
            throw HokusaiError.invalidOperation("Image has been deallocated")
        }
        return pointer
    }

    // MARK: - ImageBackend Protocol Implementation

    /// Opens a local source lazily with libvips' requested access pattern.
    static func loadFromFile(_ path: String, options: LoadOptions = LoadOptions()) throws -> VipsBackend {
        try initialize()

        guard FileManager.default.fileExists(atPath: path) else {
            throw HokusaiError.fileNotFound(path)
        }

        let output: UnsafeMutablePointer<CVips.VipsImage>?
        switch options.access {
        case .sequential:
            output = swift_vips_image_new_from_file_sequential(path)
        case .random:
            output = swift_vips_image_new_from_file(path)
        }

        guard let img = output else {
            throw HokusaiError.loadFailed("\(path): \(getLastError())")
        }

        return VipsBackend(takingOwnership: img)
    }

    /// Copies encoded bytes into native ownership and opens them lazily.
    static func loadFromBuffer(_ data: Data, options: LoadOptions = LoadOptions()) throws -> VipsBackend {
        try initialize()

        guard !data.isEmpty else {
            throw HokusaiError.invalidImageData
        }

        // The shim copies bytes into libvips-owned storage before this closure
        // returns, so lazy evaluation never borrows `Data` storage.
        let output: UnsafeMutablePointer<CVips.VipsImage>? = data.withUnsafeBytes { bytes in
            switch options.access {
            case .sequential:
                return swift_vips_image_new_from_buffer_sequential(bytes.baseAddress, data.count)
            case .random:
                return swift_vips_image_new_from_buffer(bytes.baseAddress, data.count)
            }
        }

        guard let img = output else {
            throw HokusaiError.loadFailed(getLastError())
        }

        return VipsBackend(takingOwnership: img)
    }

    /// Opens a local source through libvips' shrink-on-load thumbnail path.
    static func thumbnailFromFile(_ path: String, width: Int, options: ThumbnailOptions) throws -> VipsBackend {
        try initialize()
        let arguments = try ThumbnailArguments.validate(width: width, options: options)

        guard FileManager.default.fileExists(atPath: path) else {
            throw HokusaiError.fileNotFound(path)
        }

        var output: UnsafeMutablePointer<CVips.VipsImage>?
        let result = swift_vips_thumbnail(
            path, &output, arguments.width, arguments.height, arguments.crop, arguments.noRotate)

        guard result == 0, let img = output else {
            discardPartialImage(output)
            throw HokusaiError.loadFailed("thumbnail of \(path): \(getLastError())")
        }

        return VipsBackend(takingOwnership: img)
    }

    /// Creates a shrink-on-load thumbnail from copied encoded bytes.
    static func thumbnailFromBuffer(_ data: Data, width: Int, options: ThumbnailOptions) throws -> VipsBackend {
        try initialize()
        let arguments = try ThumbnailArguments.validate(width: width, options: options)

        guard !data.isEmpty else {
            throw HokusaiError.invalidImageData
        }

        // As with normal buffer loading, the shim copies bytes before lazy
        // thumbnail evaluation can outlive the Swift `Data` value.
        var output: UnsafeMutablePointer<CVips.VipsImage>?
        let result = data.withUnsafeBytes { bytes -> Int32 in
            swift_vips_thumbnail_buffer(
                bytes.baseAddress, data.count, &output,
                arguments.width, arguments.height, arguments.crop, arguments.noRotate)
        }

        guard result == 0, let img = output else {
            discardPartialImage(output)
            throw HokusaiError.loadFailed("thumbnail from buffer: \(getLastError())")
        }

        return VipsBackend(takingOwnership: img)
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
        case "avif", "heif", "heic":
            result = swift_vips_heifsave(pointer, path, Int32(quality ?? 80), 0, 4, 1)
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
        case "avif", "heif", "heic":
            result = swift_vips_heifsave_buffer(pointer, &buffer, &length, Int32(quality ?? 80), 1)
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

    /// Reads the current native width without forcing an encode.
    func getWidth() throws -> Int {
        let pointer = try getPointer()
        return Int(vips_image_get_width(pointer))
    }

    /// Reads the current native height without forcing an encode.
    func getHeight() throws -> Int {
        let pointer = try getPointer()
        return Int(vips_image_get_height(pointer))
    }

    /// Reads the current count of pixel bands.
    func getBands() throws -> Int {
        let pointer = try getPointer()
        return Int(vips_image_get_bands(pointer))
    }

    /// Checks the native image's alpha capability.
    func hasAlpha() throws -> Bool {
        let pointer = try getPointer()
        return vips_image_hasalpha(pointer) != 0
    }

    /// Copies scalar libvips fields and adds stable aliases used by Hokusai.
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

        // Add stable aliases where libvips exposes a native enum or resolution
        // only through its lower-level metadata dictionary.
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

    /// Copies an optional binary libvips metadata field into Swift data.
    func metadataBlob(named name: String) throws -> Data? {
        let pointer = try getPointer()
        var length = 0
        guard let copied = swift_vips_image_get_blob_copy(pointer, name, &length) else {
            return nil
        }
        defer { g_free(copied) }
        return Data(bytes: copied, count: length)
    }

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

    /// Copies and clears libvips' process-global error buffer atomically.
    ///
    /// Copying before clearing preserves the diagnostic and avoids returning a
    /// pointer into shared native storage.
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

    /// Process-wide libvips worker concurrency exposed by the legacy runtime API.
    static var concurrency: Int {
        get { Int(swift_vips_concurrency_get()) }
        set { swift_vips_concurrency_set(Int32(newValue)) }
    }
}
