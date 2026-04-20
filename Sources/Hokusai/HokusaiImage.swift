import Foundation
import CVips

/// Storage for backend image data
enum ImageData {
    case vips(VipsBackend)
}

/// Unified image wrapper with automatic backend routing
public final class HokusaiImage: @unchecked Sendable {
    private var imageData: ImageData
    private let lock = NSLock()

    /// Internal initializer with backend data
    init(backend: ImageData) {
        self.imageData = backend
    }

    // MARK: - Backend Management

    /// Ensure the image is using VipsBackend
    func ensureVipsBackend() throws -> VipsBackend {
        lock.lock()
        defer { lock.unlock() }

        switch imageData {
        case .vips(let backend):
            return backend
        }
    }

    // MARK: - Metadata Access

    /// Get image width
    public var width: Int {
        get throws {
            switch imageData {
            case .vips(let backend):
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
            }
        }
    }

    /// Get number of bands (channels)
    public var bands: Int {
        get throws {
            switch imageData {
            case .vips(let backend):
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

    /// Get extended libvips-derived metadata as key/value pairs.
    public func extendedMetadata() throws -> [String: String] {
        switch imageData {
        case .vips(let backend):
            return try backend.extendedMetadata()
        }
    }

    // MARK: - Save Operations

    /// Save image to file
    public func toFile(_ path: String, format: String? = nil, quality: Int? = nil) throws {
        switch imageData {
        case .vips(let backend):
            try backend.saveToFile(path, format: format, quality: quality)
        }
    }

    /// Convert image to data buffer
    public func toBuffer(format: String? = nil, quality: Int? = nil) throws -> Data {
        switch imageData {
        case .vips(let backend):
            return try backend.toBuffer(format: format, quality: quality)
        }
    }

    // MARK: - Get Backend (for operations)

    /// Get VipsBackend pointer (used by vips operations)
    func getVipsPointer() throws -> UnsafeMutablePointer<CVips.VipsImage> {
        let backend = try ensureVipsBackend()
        return try backend.getPointer()
    }
}
