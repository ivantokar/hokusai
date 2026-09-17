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
        let metadata = try extendedMetadata()
        let format = metadata["vips-loader"].flatMap { loader in
            ImageFormat.from(fileExtension: loader.replacingOccurrences(of: "load", with: ""))
        }
        return ImageMetadata(
            width: try width,
            height: try height,
            channels: try bands,
            format: format,
            space: metadata["interpretationNick"],
            hasAlpha: try hasAlpha,
            orientation: metadata["orientation"].flatMap(Int.init),
            density: metadata["xresDpi"].flatMap(Double.init),
            pages: metadata["n-pages"].flatMap(Int.init),
            size: metadata["sizeof_header"].flatMap(Int.init),
            colorSpace: Self.colorSpace(from: metadata["interpretationNick"]),
            densityXY: Self.density(from: metadata),
            pageHeight: metadata["page-height"].flatMap(Int.init),
            isAnimated: (metadata["n-pages"].flatMap(Int.init) ?? 1) > 1,
            exif: try metadataBlob(named: "exif-data"),
            iccProfile: try metadataBlob(named: "icc-profile-data"),
            xmp: try metadataBlob(named: "xmp-data")
        )
    }

    /// Returns a best-effort view of libvips metadata fields.
    ///
    /// Prefer ``metadata()`` for stable application code. This compatibility
    /// API exposes loader-specific keys and normalized convenience aliases.
    public func extendedMetadata() throws -> [String: String] {
        switch imageData {
        case .vips(let backend):
            return try backend.extendedMetadata()
        }
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

    /// Copies one optional binary metadata block out of the native image.
    private func metadataBlob(named name: String) throws -> Data? {
        switch imageData {
        case .vips(let backend): return try backend.metadataBlob(named: name)
        }
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
        let width = try self.width
        let height = try self.height
        let geometry = try PDFGeometry.resolve(imageWidth: width, imageHeight: height, options: options)
        let pointer = try ensureVipsBackend().getPointer()
        var buffer: UnsafeMutableRawPointer?
        var length = 0
        guard swift_vips_pdfsave_buffer(
            pointer, &buffer, &length,
            geometry.pageWidth, geometry.pageHeight,
            geometry.imageX, geometry.imageY,
            geometry.imageWidth, geometry.imageHeight
        ) == 0, let buffer else {
            if let buffer { g_free(buffer) }
            throw HokusaiError.saveFailed(VipsBackend.getLastError())
        }
        defer { g_free(buffer) }
        return Data(bytes: buffer, count: length)
    }

    // MARK: - Get Backend (for operations)

    /// Returns the native pointer for internal operation adapters.
    func getVipsPointer() throws -> UnsafeMutablePointer<CVips.VipsImage> {
        let backend = try ensureVipsBackend()
        return try backend.getPointer()
    }
}

/// Calculated page and centered-raster geometry for Cairo-backed PDF output.
private struct PDFGeometry {
    let pageWidth: Double
    let pageHeight: Double
    let imageX: Double
    let imageY: Double
    let imageWidth: Double
    let imageHeight: Double

    /// Validates page options and scales the source to fit without distortion.
    static func resolve(imageWidth: Int, imageHeight: Int, options: PDFOptions) throws -> Self {
        guard options.dpi.isFinite, options.dpi > 0 else {
            throw HokusaiError.invalidOption(name: "dpi", reason: "must be a finite value greater than zero")
        }
        let sourceWidth = Double(imageWidth)
        let sourceHeight = Double(imageHeight)
        let page: (Double, Double)
        switch options.pageSize {
        case .image:
            page = (sourceWidth / options.dpi * 72, sourceHeight / options.dpi * 72)
        case .a4:
            page = (595.276, 841.890)
        case .letter:
            page = (612, 792)
        case .points(let width, let height):
            guard width.isFinite, height.isFinite, width > 0, height > 0 else {
                throw HokusaiError.invalidOption(name: "pageSize", reason: "point dimensions must be finite values greater than zero")
            }
            page = (width, height)
        }
        let scale = min(page.0 / sourceWidth, page.1 / sourceHeight)
        let renderedWidth = sourceWidth * scale
        let renderedHeight = sourceHeight * scale
        return Self(
            pageWidth: page.0, pageHeight: page.1,
            imageX: (page.0 - renderedWidth) / 2,
            imageY: (page.1 - renderedHeight) / 2,
            imageWidth: renderedWidth, imageHeight: renderedHeight
        )
    }
}
