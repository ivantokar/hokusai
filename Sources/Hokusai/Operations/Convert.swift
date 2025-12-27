import Foundation
import CVips

extension HokusaiImage {
    /// Convert image to specified format with quality/compression options
    public func toFormat(_ format: ImageFormat, quality: Int? = nil, compression: Int? = nil) throws -> HokusaiImage {
        // Note: Actual format conversion happens during save
        // This method returns self but marks the desired format for later use
        // We'll implement actual conversion in the save methods
        return self
    }

    /// Save image to file
    public func toFile(_ path: String, options: SaveOptions = SaveOptions()) throws {
        let pointer = try ensureVipsBackend().getPointer()

        // Determine format from path extension or options
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

            let result = swift_vips_pngsave(pointer, path, compression, Int32(interlace))
            guard result == 0 else {
                throw HokusaiError.saveFailed(VipsBackend.getLastError())
            }

        case .webp:
            let quality = Int32(options.quality ?? 80)
            let lossless = options.lossless ? 1 : 0
            let effort = Int32(options.effort ?? 4)

            let result = swift_vips_webpsave(pointer, path, quality, Int32(lossless), effort)
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

            let result = swift_vips_heifsave(pointer, path, quality, Int32(lossless), effort)
            guard result == 0 else {
                throw HokusaiError.saveFailed(VipsBackend.getLastError())
            }

        case .heif:
            let quality = Int32(options.quality ?? 80)
            let lossless = 0
            let effort = Int32(4)

            let result = swift_vips_heifsave(pointer, path, quality, Int32(lossless), effort)
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

    /// Save image to Data buffer
    public func toBuffer(options: SaveOptions = SaveOptions()) throws -> Data {
        let pointer = try ensureVipsBackend().getPointer()

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
                quality
            )

        case .png:
            let compression = Int32(options.compression ?? 6)
            result = swift_vips_pngsave_buffer(
                pointer,
                &buffer,
                &bufferSize,
                compression
            )

        case .webp:
            let quality = Int32(options.quality ?? 80)
            let lossless = options.lossless ? 1 : 0
            result = swift_vips_webpsave_buffer(
                pointer,
                &buffer,
                &bufferSize,
                quality,
                Int32(lossless)
            )

        case .tiff:
            result = swift_vips_tiffsave_buffer(
                pointer,
                &buffer,
                &bufferSize
            )

        case .avif, .heif:
            let quality = Int32(options.quality ?? 80)
            result = swift_vips_heifsave_buffer(
                pointer,
                &buffer,
                &bufferSize,
                quality
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
            // Debug: include result code in error
            let debugMsg = errorMsg.isEmpty ? "result code: \(result)" : errorMsg
            throw HokusaiError.saveFailed(debugMsg)
        }

        let data = Data(bytes: buf, count: bufferSize)
        g_free(buf)

        return data
    }

    /// Convenience method to save as JPEG
    public func toJpeg(path: String, quality: Int = 85) throws {
        var options = SaveOptions()
        options.format = .jpeg
        options.quality = quality
        try toFile(path, options: options)
    }

    /// Convenience method to save as PNG
    public func toPng(path: String, compression: Int = 6) throws {
        var options = SaveOptions()
        options.format = .png
        options.compression = compression
        try toFile(path, options: options)
    }

    /// Convenience method to save as WebP
    public func toWebp(path: String, quality: Int = 80, lossless: Bool = false) throws {
        var options = SaveOptions()
        options.format = .webp
        options.quality = quality
        options.lossless = lossless
        try toFile(path, options: options)
    }
}
