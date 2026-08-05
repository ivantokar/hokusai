import Foundation
import CVips

/// PURPOSE: Storage for backend image data
enum ImageData {
    case vips(VipsBackend)
}

/// PURPOSE: Unified image wrapper used by all public image operations.
/// CONSTRAINTS:
/// - Backed by libvips only.
/// - Keep this as a thin façade over backend operations.
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

    /// PURPOSE: Internal initializer with backend data
    init(backend: ImageData) {
        self.imageData = backend
    }

    // MARK: - Backend Management

    /// PURPOSE: Resolve and return the active libvips backend instance.
    /// OUTPUT: Live `VipsBackend` for this image.
    func ensureVipsBackend() throws -> VipsBackend {
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

    /// PURPOSE: Return extended libvips-derived metadata key/value map.
    /// OUTPUT: Best-effort dictionary with normalized convenience aliases.
    public func extendedMetadata() throws -> [String: String] {
        switch imageData {
        case .vips(let backend):
            return try backend.extendedMetadata()
        }
    }

    private static func colorSpace(from interpretation: String?) -> ColorSpace? {
        switch interpretation?.lowercased() {
        case "srgb", "rgb16": .sRGB
        case "b-w", "grey16": .grayscale
        default: nil
        }
    }

    private static func density(from metadata: [String: String]) -> ImageDensity? {
        guard let horizontal = metadata["xresDpi"].flatMap(Double.init),
              let vertical = metadata["yresDpi"].flatMap(Double.init) else {
            return nil
        }
        return ImageDensity(horizontal: horizontal, vertical: vertical)
    }

    private func metadataBlob(named name: String) throws -> Data? {
        switch imageData {
        case .vips(let backend): return try backend.metadataBlob(named: name)
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

    /// PURPOSE: Get VipsBackend pointer (used by vips operations)
    func getVipsPointer() throws -> UnsafeMutablePointer<CVips.VipsImage> {
        let backend = try ensureVipsBackend()
        return try backend.getPointer()
    }
}

private struct PDFGeometry {
    let pageWidth: Double
    let pageHeight: Double
    let imageX: Double
    let imageY: Double
    let imageWidth: Double
    let imageHeight: Double

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
