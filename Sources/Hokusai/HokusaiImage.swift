import Foundation
import CVips
import CImageMagick

/// Storage for backend image data
enum ImageData {
    case vips(VipsBackend)
    case magick(MagickBackend)
}

/// Unified image wrapper with automatic backend routing
public final class HokusaiImage: @unchecked Sendable {
    private var imageData: ImageData
    private let lock = NSLock()

    /// Internal initializer with backend data
    init(backend: ImageData) {
        self.imageData = backend
    }

    /// Current backend type
    private var currentBackend: BackendType {
        switch imageData {
        case .vips: return .vips
        case .magick: return .magick
        }
    }

    deinit {
        lock.lock()
        defer { lock.unlock() }
        // Backend cleanup happens in VipsBackend/MagickBackend deinit
    }

    // MARK: - Backend Management

    /// Ensure the image is using VipsBackend (convert if needed)
    func ensureVipsBackend() throws -> VipsBackend {
        print("[ensureVipsBackend] START")
        fflush(stdout)

        print("[ensureVipsBackend] Acquiring lock...")
        fflush(stdout)
        lock.lock()
        defer { lock.unlock() }
        print("[ensureVipsBackend] Lock acquired")
        fflush(stdout)

        print("[ensureVipsBackend] Checking imageData type...")
        fflush(stdout)

        switch imageData {
        case .vips(let backend):
            print("[ensureVipsBackend] Already VipsBackend, returning")
            fflush(stdout)
            return backend
        case .magick(let backend):
            print("[ensureVipsBackend] MagickBackend detected, converting to Vips...")
            fflush(stdout)
            // Convert magick → vips
            let vipsBackend = try magickToVips(backend)
            imageData = .vips(vipsBackend)
            print("[ensureVipsBackend] Conversion complete")
            fflush(stdout)
            return vipsBackend
        }
    }

    /// Ensure the image is using MagickBackend (convert if needed)
    func ensureMagickBackend() throws -> MagickBackend {
        lock.lock()
        defer { lock.unlock() }

        switch imageData {
        case .magick(let backend):
            return backend
        case .vips(let backend):
            // Convert vips → magick
            let magickBackend = try vipsToMagick(backend)
            imageData = .magick(magickBackend)
            return magickBackend
        }
    }

    // MARK: - Backend Conversion

    /// Convert VipsBackend to MagickBackend via PNG buffer
    private func vipsToMagick(_ vipsBackend: VipsBackend) throws -> MagickBackend {
        // Convert to PNG buffer (lossless, fast compression)
        let buffer = try vipsBackend.toBuffer(format: "png", quality: 0)

        // Load into MagickWand
        return try MagickBackend.loadFromBuffer(buffer)
    }

    /// Convert MagickBackend to VipsBackend via PNG buffer
    private func magickToVips(_ magickBackend: MagickBackend) throws -> VipsBackend {
        // Convert to PNG buffer (lossless)
        let buffer = try magickBackend.toBuffer(format: "png", quality: 0)

        // Load into libvips
        return try VipsBackend.loadFromBuffer(buffer)
    }

    // MARK: - Metadata Access

    /// Get image width
    public var width: Int {
        get throws {
            switch imageData {
            case .vips(let backend):
                return try backend.getWidth()
            case .magick(let backend):
                return try backend.getWidth()
            }
        }
    }

    /// Get image height
    public var height: Int {
        get throws {
            switch imageData {
            case .vips(let backend):
                return try backend.getHeight()
            case .magick(let backend):
                return try backend.getHeight()
            }
        }
    }

    /// Get number of bands (channels)
    public var bands: Int {
        get throws {
            switch imageData {
            case .vips(let backend):
                return try backend.getBands()
            case .magick(let backend):
                return try backend.getBands()
            }
        }
    }

    /// Check if image has alpha channel
    public var hasAlpha: Bool {
        get throws {
            switch imageData {
            case .vips(let backend):
                return try backend.hasAlpha()
            case .magick(let backend):
                return try backend.hasAlpha()
            }
        }
    }

    /// Get image metadata
    public func metadata() throws -> ImageMetadata {
        return ImageMetadata(
            width: try width,
            height: try height,
            channels: try bands,
            format: nil,  // TODO: Detect format
            space: nil,   // TODO: Get color space
            hasAlpha: try hasAlpha,
            orientation: nil,  // TODO: Get EXIF orientation
            density: nil,      // TODO: Get DPI
            pages: nil,        // TODO: Get page count
            size: nil
        )
    }

    // MARK: - Save Operations

    /// Save image to file
    public func toFile(_ path: String, format: String? = nil, quality: Int? = nil) throws {
        switch imageData {
        case .vips(let backend):
            try backend.saveToFile(path, format: format, quality: quality)
        case .magick(let backend):
            try backend.saveToFile(path, format: format, quality: quality)
        }
    }

    /// Convert image to data buffer
    public func toBuffer(format: String? = nil, quality: Int? = nil) throws -> Data {
        switch imageData {
        case .vips(let backend):
            return try backend.toBuffer(format: format, quality: quality)
        case .magick(let backend):
            return try backend.toBuffer(format: format, quality: quality)
        }
    }

    // MARK: - Get Backend (for operations)

    /// Get VipsBackend pointer (used by vips operations)
    func getVipsPointer() throws -> UnsafeMutablePointer<CVips.VipsImage> {
        let backend = try ensureVipsBackend()
        return try backend.getPointer()
    }

    /// Get MagickBackend wand (used by magick operations)
    func getMagickWand() throws -> OpaquePointer {
        let backend = try ensureMagickBackend()
        return try backend.getWandPointer()
    }
}
