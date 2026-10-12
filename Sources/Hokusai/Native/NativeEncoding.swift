import Foundation
import CVips

extension NativeImage {
    /// Encodes and writes this image to `path`.
    ///
    /// A `SaveOptions.format` overrides extension inference. The call is
    /// synchronous and does not create parent directories.
    func write(to path: String, options: SaveOptions) throws {

        // Explicit format wins; otherwise use the destination extension.
        let format = options.format ?? ImageFormat.from(fileExtension: (path as NSString).pathExtension)

        guard let outputFormat = format else {
            throw HokusaiError.unsupportedFormat("Could not determine format from path: \(path)")
        }

        switch outputFormat {
        case .jpeg:
            let quality = Int32(options.quality ?? 85)
            let interlace = options.progressive ? 1 : 0
            let strip = options.stripMetadata ? 1 : 0

            let result = swift_vips_jpegsave(pointer, path, quality, Int32(interlace), Int32(strip))
            guard result == 0 else {
                throw HokusaiError.saveFailed(VipsBackend.getLastError())
            }

        case .png:
            let compression = Int32(options.compression ?? 6)
            let interlace = options.progressive ? 1 : 0

            let result = swift_vips_pngsave(pointer, path, compression, Int32(interlace), options.stripMetadata ? 1 : 0)
            guard result == 0 else {
                throw HokusaiError.saveFailed(VipsBackend.getLastError())
            }

        case .webp:
            let quality = Int32(options.quality ?? 80)
            let lossless = options.lossless ? 1 : 0
            let effort = Int32(options.effort ?? 4)

            let result = swift_vips_webpsave(pointer, path, quality, Int32(lossless), effort, options.stripMetadata ? 1 : 0)
            guard result == 0 else {
                throw HokusaiError.saveFailed(VipsBackend.getLastError())
            }

        case .tiff:
            let compression = Int32(options.compression ?? 0)

            let result = swift_vips_tiffsave(pointer, path, compression)
            guard result == 0 else {
                throw HokusaiError.saveFailed(VipsBackend.getLastError())
            }

        case .avif:
            let quality = Int32(options.quality ?? 80)
            let lossless = options.lossless ? 1 : 0
            let effort = Int32(options.effort ?? 4)

            let result = swift_vips_heifsave(pointer, path, quality, Int32(lossless), effort, options.stripMetadata ? 1 : 0, 1)
            guard result == 0 else {
                throw HokusaiError.saveFailed(VipsBackend.getLastError())
            }

        case .heif:
            let quality = Int32(options.quality ?? 80)
            let lossless = 0
            let effort = Int32(4)

            let result = swift_vips_heifsave(pointer, path, quality, Int32(lossless), effort, options.stripMetadata ? 1 : 0, 0)
            guard result == 0 else {
                throw HokusaiError.saveFailed(VipsBackend.getLastError())
            }

        case .gif:
            let result = swift_vips_gifsave(pointer, path)
            guard result == 0 else {
                throw HokusaiError.saveFailed(VipsBackend.getLastError())
            }

        default:
            throw HokusaiError.unsupportedFormat("Saving to \(outputFormat.rawValue) is not yet implemented")
        }
    }

    /// Encodes this image into an owned data buffer.
    ///
    /// Buffers have no filename, so callers must select `options.format`.
    func encoded(options: SaveOptions) throws -> Data {

        guard let format = options.format else {
            throw HokusaiError.invalidOperation("Must specify format when saving to buffer")
        }

        var buffer: UnsafeMutableRawPointer?
        var bufferSize: Int = 0

        let result: Int32

        switch format {
        case .jpeg:
            let quality = Int32(options.quality ?? 85)
            result = swift_vips_jpegsave_buffer(
                pointer,
                &buffer,
                &bufferSize,
                quality,
                options.stripMetadata ? 1 : 0
            )

        case .png:
            let compression = Int32(options.compression ?? 6)
            result = swift_vips_pngsave_buffer(
                pointer,
                &buffer,
                &bufferSize,
                compression,
                options.stripMetadata ? 1 : 0
            )

        case .webp:
            let quality = Int32(options.quality ?? 80)
            let lossless = options.lossless ? 1 : 0
            let effort = Int32(options.effort ?? 4)
            result = swift_vips_webpsave_buffer(
                pointer,
                &buffer,
                &bufferSize,
                quality,
                Int32(lossless),
                effort,
                options.stripMetadata ? 1 : 0
            )

        case .tiff:
            result = swift_vips_tiffsave_buffer(
                pointer,
                &buffer,
                &bufferSize
            )

        case .avif, .heif:
            // The codec must be explicit: buffers have no suffix to infer it from.
            let quality = Int32(options.quality ?? 80)
            let lossless = format == .avif && options.lossless ? 1 : 0
            let effort = Int32(format == .avif ? options.effort ?? 4 : 4)
            result = swift_vips_heifsave_buffer(
                pointer,
                &buffer,
                &bufferSize,
                quality,
                Int32(lossless),
                effort,
                options.stripMetadata ? 1 : 0,
                format == .avif ? 1 : 0
            )

        case .gif:
            result = swift_vips_gifsave_buffer(
                pointer,
                &buffer,
                &bufferSize
            )

        default:
            throw HokusaiError.unsupportedFormat("Saving to \(format.rawValue) buffer is not yet implemented")
        }

        guard result == 0, let buf = buffer else {
            let errorMsg = VipsBackend.getLastError()
            // Native encoders sometimes provide no diagnostic; retain the
            // result code in that case so callers still receive actionable context.
            let debugMsg = errorMsg.isEmpty ? "result code: \(result)" : errorMsg
            throw HokusaiError.saveFailed(debugMsg)
        }

        let data = Data(bytes: buf, count: bufferSize)
        g_free(buf)

        return data
    }

    /// Renders the image as a single-page PDF using Cairo.
    func pdf(options: PDFOptions) throws -> Data {
        let geometry = try PDFGeometry.resolve(imageWidth: width, imageHeight: height, options: options)
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
