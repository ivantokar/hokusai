import Foundation
import CVips

/// The concrete native storage used by a legacy image handle.
enum ImageData {
    case vips(VipsBackend)
}

/// A legacy reference-style image handle backed by an immutable libvips graph.
///
/// New code should prefer the value-semantic ``Hokusai`` pipeline. This type
/// remains public for migration compatibility and for the optimized legacy
/// thumbnail API. Every transform returns a new handle; the receiver is never
/// mutated.
///
/// Concurrency policy (`@unchecked Sendable`): a `HokusaiImage` is a handle to
/// an immutable libvips image pipeline. The wrapper never mutates its backend
/// reference after initialization (`imageData` is `let`), operations always
/// produce new images, and libvips images are safe to read from multiple
/// threads concurrently — libvips operations never mutate their inputs. The
/// only mutable native state (the owned pointer) lives in `VipsBackend`
/// behind a lock. This policy is exercised by `LifecycleConcurrencyTests`.
public final class HokusaiImage: @unchecked Sendable {
    private let imageData: ImageData

    /// Creates a handle that owns the supplied backend storage.
    init(backend: ImageData) {
        self.imageData = backend
    }

    /// Wraps a native image produced by a shared native operation.
    convenience init(native: NativeImage) {
        self.init(backend: .vips(VipsBackend(native: native)))
    }

    /// Returns the native image backing this legacy handle.
    func native() throws -> NativeImage {
        try ensureVipsBackend().native
    }

    // MARK: - Backend Management

    /// Returns the backend that owns this image's native pointer.
    func ensureVipsBackend() throws -> VipsBackend {
        switch imageData {
        case .vips(let backend):
            return backend
        }
    }

    // MARK: - Metadata Access

    /// The current image width in pixels.
    public var width: Int {
        get throws {
            switch imageData {
            case .vips(let backend):
                return try backend.getWidth()
            }
        }
    }

    /// The current image height in pixels.
    public var height: Int {
        get throws {
            switch imageData {
            case .vips(let backend):
                return try backend.getHeight()
            }
        }
    }

    /// The number of channels in the current image.
    public var bands: Int {
        get throws {
            switch imageData {
            case .vips(let backend):
                return try backend.getBands()
            }
        }
    }

    /// Whether the current image has an alpha channel.
    public var hasAlpha: Bool {
        get throws {
            switch imageData {
            case .vips(let backend):
                return try backend.hasAlpha()
            }
        }
    }

    /// Returns normalized metadata available from the current libvips image.
    ///
    /// Optional fields remain `nil` when the loader did not expose them. This
    /// call may inspect headers but does not encode an output image.
    public func metadata() throws -> ImageMetadata {
        try native().metadata()
    }

    /// Returns a best-effort view of libvips metadata fields.
    ///
    /// Prefer ``metadata()`` for stable application code. This compatibility
    /// API exposes loader-specific keys and normalized convenience aliases.
    public func extendedMetadata() throws -> [String: String] {
        try native().extendedMetadata()
    }

    // MARK: - Save Operations

    /// Encodes this legacy handle and writes it to a file.
    ///
    /// The format is inferred from `path` unless supplied explicitly. This is
    /// synchronous compatibility behavior; prefer ``Hokusai/write(to:)`` in
    /// new async server code.
    public func toFile(_ path: String, format: String? = nil, quality: Int? = nil) throws {
        switch imageData {
        case .vips(let backend):
            try backend.saveToFile(path, format: format, quality: quality)
        }
    }

    /// Encodes this legacy handle into owned bytes.
    ///
    /// The default format is JPEG when `format` is omitted. Prefer a 1.0
    /// pipeline with an explicit encoder and ``Hokusai/data()`` for new code.
    public func toBuffer(format: String? = nil, quality: Int? = nil) throws -> Data {
        switch imageData {
        case .vips(let backend):
            return try backend.toBuffer(format: format, quality: quality)
        }
    }

    /// Renders the image as a single-page PDF using Cairo.
    func toPDF(options: PDFOptions) throws -> Data {
        try native().pdf(options: options)
    }

    // MARK: - Get Backend (for operations)

    /// Returns the native pointer for internal operation adapters.
    func getVipsPointer() throws -> UnsafeMutablePointer<CVips.VipsImage> {
        let backend = try ensureVipsBackend()
        return try backend.getPointer()
    }
}
