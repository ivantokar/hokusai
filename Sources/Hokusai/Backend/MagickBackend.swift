import Foundation
import CImageMagick

/// ImageMagick backend implementation for advanced text rendering
final class MagickBackend: ImageBackend {
    private var wandPointer: OpaquePointer?
    private let lock = NSLock()

    /// Initialize ImageMagick (call once at app startup)
    static func initialize() {
        hokusai_magick_init()
    }

    /// Shutdown ImageMagick (call at app teardown)
    static func shutdown() {
        hokusai_magick_terminate()
    }

    /// Internal initializer with MagickWand pointer
    init(takingOwnership wand: OpaquePointer) {
        self.wandPointer = wand
    }

    deinit {
        lock.lock()
        defer { lock.unlock() }

        if let wand = wandPointer {
            hokusai_destroy_wand(wand)
            wandPointer = nil
        }
    }

    /// Get the underlying wand pointer (for internal use)
    func getWandPointer() throws -> OpaquePointer {
        lock.lock()
        defer { lock.unlock() }

        guard let wand = wandPointer else {
            throw HokusaiError.invalidOperation("Wand has been deallocated")
        }
        return wand
    }

    // MARK: - ImageBackend Protocol Implementation

    static func loadFromFile(_ path: String) throws -> MagickBackend {
        guard FileManager.default.fileExists(atPath: path) else {
            throw HokusaiError.fileNotFound(path)
        }

        guard let wand = hokusai_new_wand() else {
            throw HokusaiError.memoryAllocationFailed
        }

        let result = hokusai_read_image(wand, path)
        guard result == MagickTrue else {
            let error = getMagickError(wand)
            hokusai_destroy_wand(wand)
            throw HokusaiError.loadFailed(error)
        }

        return MagickBackend(takingOwnership: wand)
    }

    static func loadFromBuffer(_ data: Data) throws -> MagickBackend {
        guard !data.isEmpty else {
            throw HokusaiError.invalidImageData
        }

        guard let wand = hokusai_new_wand() else {
            throw HokusaiError.memoryAllocationFailed
        }

        let result = data.withUnsafeBytes { bytes in
            hokusai_read_image_blob(wand, bytes.baseAddress, data.count)
        }

        guard result == MagickTrue else {
            let error = getMagickError(wand)
            hokusai_destroy_wand(wand)
            throw HokusaiError.loadFailed(error)
        }

        return MagickBackend(takingOwnership: wand)
    }

    func saveToFile(_ path: String, format: String?, quality: Int?) throws {
        let wand = try getWandPointer()

        // Set format if specified
        if let fmt = format {
            let result = hokusai_set_image_format(wand, fmt.uppercased())
            guard result == MagickTrue else {
                throw HokusaiError.saveFailed(Self.getMagickError(wand))
            }
        }

        let result = hokusai_write_image(wand, path)
        guard result == MagickTrue else {
            throw HokusaiError.saveFailed(Self.getMagickError(wand))
        }
    }

    func toBuffer(format: String?, quality: Int?) throws -> Data {
        let wand = try getWandPointer()

        // Set format if specified
        if let fmt = format {
            let result = hokusai_set_image_format(wand, fmt.uppercased())
            guard result == MagickTrue else {
                throw HokusaiError.saveFailed(Self.getMagickError(wand))
            }
        }

        var length: Int = 0
        guard let blob = hokusai_get_image_blob(wand, &length) else {
            throw HokusaiError.saveFailed(Self.getMagickError(wand))
        }

        defer { hokusai_relinquish_memory(blob) }
        return Data(bytes: blob, count: length)
    }

    func getWidth() throws -> Int {
        let wand = try getWandPointer()
        return Int(hokusai_get_image_width(wand))
    }

    func getHeight() throws -> Int {
        let wand = try getWandPointer()
        return Int(hokusai_get_image_height(wand))
    }

    func getBands() throws -> Int {
        // ImageMagick doesn't have a direct "bands" concept like vips
        // Typically returns 3 for RGB, 4 for RGBA
        // For now, return 3 as a reasonable default
        return 3
    }

    func hasAlpha() throws -> Bool {
        // This would require checking the image's alpha channel
        // For simplicity, assume images can have alpha
        return true
    }

    // MARK: - Text Rendering (ImageMagick-specific)

    func drawText(
        _ text: String,
        x: Double,
        y: Double,
        options: TextOptions
    ) throws {
        let wand = try getWandPointer()

        // Create drawing wand
        guard let drawingWand = hokusai_new_drawing_wand() else {
            throw HokusaiError.memoryAllocationFailed
        }
        defer { hokusai_destroy_drawing_wand(drawingWand) }

        // Set font (support TTF file paths)
        hokusai_draw_set_font(drawingWand, options.font)
        hokusai_draw_set_font_size(drawingWand, Double(options.fontSize))

        // Set fill color
        let fillWand = hokusai_new_pixel_wand()!
        defer { hokusai_destroy_pixel_wand(fillWand) }

        hokusai_pixel_set_red(fillWand, options.color[0] / 255.0)
        hokusai_pixel_set_green(fillWand, options.color[1] / 255.0)
        hokusai_pixel_set_blue(fillWand, options.color[2] / 255.0)
        hokusai_pixel_set_alpha(fillWand, options.color[3] / 255.0)
        hokusai_draw_set_fill_color(drawingWand, fillWand)

        // Set stroke if provided
        if let strokeColor = options.strokeColor,
           let strokeWidth = options.strokeWidth {
            let strokeWand = hokusai_new_pixel_wand()!
            defer { hokusai_destroy_pixel_wand(strokeWand) }

            hokusai_pixel_set_red(strokeWand, strokeColor[0] / 255.0)
            hokusai_pixel_set_green(strokeWand, strokeColor[1] / 255.0)
            hokusai_pixel_set_blue(strokeWand, strokeColor[2] / 255.0)
            hokusai_pixel_set_alpha(strokeWand, strokeColor[3] / 255.0)

            hokusai_draw_set_stroke_color(drawingWand, strokeWand)
            hokusai_draw_set_stroke_width(drawingWand, strokeWidth)
        }

        // Set kerning if provided
        if let kerning = options.kerning {
            hokusai_draw_set_text_kerning(drawingWand, kerning)
        }

        // Set antialiasing
        hokusai_draw_set_text_antialiasing(drawingWand, options.antialiasing ? MagickTrue : MagickFalse)

        // Set gravity if provided
        if let gravity = options.gravity {
            let gravityType = mapGravity(gravity)
            hokusai_draw_set_gravity(drawingWand, gravityType)
        }

        // Set text alignment
        let alignment = mapAlignment(options.align)
        hokusai_draw_set_text_alignment(drawingWand, alignment)

        // Annotate image with text
        let angle = options.rotation ?? 0.0
        let result = hokusai_annotate_image(wand, drawingWand, x, y, angle, text)

        guard result == MagickTrue else {
            throw HokusaiError.textRenderingFailed(Self.getMagickError(wand))
        }
    }

    // MARK: - Helper Methods

    private static func getMagickError(_ wand: OpaquePointer) -> String {
        var severity: ExceptionType = UndefinedException
        guard let error = hokusai_get_exception(wand, &severity) else {
            return "Unknown ImageMagick error"
        }
        defer { hokusai_relinquish_memory(error) }
        return String(cString: error)
    }

    private func mapGravity(_ gravity: TextGravity) -> GravityType {
        switch gravity {
        case .center: return CenterGravity
        case .north: return NorthGravity
        case .south: return SouthGravity
        case .east: return EastGravity
        case .west: return WestGravity
        case .northEast: return NorthEastGravity
        case .northWest: return NorthWestGravity
        case .southEast: return SouthEastGravity
        case .southWest: return SouthWestGravity
        }
    }

    private func mapAlignment(_ alignment: TextAlignment) -> AlignType {
        switch alignment {
        case .left: return LeftAlign
        case .center: return CenterAlign
        case .right: return RightAlign
        }
    }

    /// Get ImageMagick version
    static var version: String {
        var versionNumber: Int = 0
        guard let versionStr = hokusai_get_version(&versionNumber) else {
            return "unknown"
        }
        return String(cString: versionStr)
    }
}
