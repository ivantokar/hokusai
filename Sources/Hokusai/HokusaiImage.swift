import Foundation
import CVips

/// PURPOSE: Storage for backend image data
enum ImageData {
    case vips(VipsBackend)
}

/// PURPOSE: Unified image wrapper used by all public image operations.
/// CONSTRAINTS:
/// - Backed by libvips only.
/// - All backend access must remain thread-safe.
/// AI HINTS:
/// - Preserve lock boundaries around mutable backend state.
/// - Keep this as a thin façade over backend operations.
public final class HokusaiImage: @unchecked Sendable {
    private var imageData: ImageData
    private let lock = NSLock()

    /// PURPOSE: Internal initializer with backend data
    init(backend: ImageData) {
        self.imageData = backend
    }

    // MARK: - Backend Management

    /// PURPOSE: Resolve and return the active libvips backend instance.
    /// OUTPUT: Live `VipsBackend` for this image.
    /// CONSTRAINTS: Must hold lock while reading backend storage.
    func ensureVipsBackend() throws -> VipsBackend {
        lock.lock()
        defer { lock.unlock() }

        switch imageData {
        case .vips(let backend):
            return backend
        }
    }

    // MARK: - Metadata Access

    /// PURPOSE: Get image width
    public var width: Int {
        get throws {
            switch imageData {
            case .vips(let backend):
                return try backend.getWidth()
            }
        }
    }

    /// PURPOSE: Get image height
    public var height: Int {
        get throws {
            switch imageData {
            case .vips(let backend):
                return try backend.getHeight()
            }
        }
    }

    /// PURPOSE: Get number of bands (channels)
    public var bands: Int {
        get throws {
            switch imageData {
            case .vips(let backend):
                return try backend.getBands()
            }
        }
    }

    /// PURPOSE: Check if image has alpha channel
    public var hasAlpha: Bool {
        get throws {
            switch imageData {
            case .vips(let backend):
                return try backend.hasAlpha()
            }
        }
    }

    /// PURPOSE: Return normalized metadata common to all API consumers.
    /// OUTPUT: `ImageMetadata` with dimensions/channels/alpha and optional fields.
    /// AI HINTS:
    /// - Keep optional fields nil unless we can extract them reliably.
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

    /// PURPOSE: Return extended libvips-derived metadata key/value map.
    /// OUTPUT: Best-effort dictionary with normalized convenience aliases.
    public func extendedMetadata() throws -> [String: String] {
        switch imageData {
        case .vips(let backend):
            return try backend.extendedMetadata()
        }
    }

    // MARK: - Save Operations

    /// PURPOSE: Encode and write image to file.
    /// INPUT: Destination `path`; optional `format` and `quality` overrides.
    /// SIDE EFFECTS: Filesystem write.
    public func toFile(_ path: String, format: String? = nil, quality: Int? = nil) throws {
        switch imageData {
        case .vips(let backend):
            try backend.saveToFile(path, format: format, quality: quality)
        }
    }

    /// PURPOSE: Encode image into an in-memory buffer.
    /// OUTPUT: Encoded bytes in requested or inferred format.
    public func toBuffer(format: String? = nil, quality: Int? = nil) throws -> Data {
        switch imageData {
        case .vips(let backend):
            return try backend.toBuffer(format: format, quality: quality)
        }
    }

    // MARK: - Get Backend (for operations)

    /// PURPOSE: Get VipsBackend pointer (used by vips operations)
    func getVipsPointer() throws -> UnsafeMutablePointer<CVips.VipsImage> {
        let backend = try ensureVipsBackend()
        return try backend.getPointer()
    }
}
