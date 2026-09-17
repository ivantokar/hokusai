import Foundation
import CVips

extension HokusaiImage {
    /// Legacy placeholder for selecting an output format.
    ///
    /// Conversion happens only when a synchronous legacy terminal is called.
    /// New code should use ``Hokusai/encode(as:)`` or a typed encoder on the
    /// immutable pipeline, which records this choice explicitly.
    public func toFormat(_ format: ImageFormat, quality: Int? = nil, compression: Int? = nil) throws -> HokusaiImage {
        // This legacy method cannot persist encoder configuration, so preserve
        // its historic no-op behavior rather than pretending conversion happened.
        return self
    }

    /// Encodes and writes this legacy image to `path`.
    ///
    /// A `SaveOptions.format` overrides extension inference. The call is
    /// synchronous and does not create parent directories.
    public func toFile(_ path: String, options: SaveOptions = SaveOptions()) throws {
        let pointer = try ensureVipsBackend().getPointer()

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

            let result = swift_vips_heifsave(pointer, path, quality, Int32(lossless), effort, options.stripMetadata ? 1 : 0)
            guard result == 0 else {
                throw HokusaiError.saveFailed(VipsBackend.getLastError())
            }

        case .heif:
            let quality = Int32(options.quality ?? 80)
            let lossless = 0
            let effort = Int32(4)

            let result = swift_vips_heifsave(pointer, path, quality, Int32(lossless), effort, options.stripMetadata ? 1 : 0)
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

    /// Encodes this legacy image into an owned data buffer.
    ///
    /// Buffers have no filename, so callers must select `options.format`.
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
            let quality = Int32(options.quality ?? 80)
            result = swift_vips_heifsave_buffer(
                pointer,
                &buffer,
                &bufferSize,
                quality,
                options.stripMetadata ? 1 : 0
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

    /// Writes a JPEG using the supplied quality.
    public func toJpeg(path: String, quality: Int = 85) throws {
        var options = SaveOptions()
        options.format = .jpeg
        options.quality = quality
        try toFile(path, options: options)
    }

    /// Writes a PNG using the supplied compression level.
    public func toPng(path: String, compression: Int = 6) throws {
        var options = SaveOptions()
        options.format = .png
        options.compression = compression
        try toFile(path, options: options)
    }

    /// Writes a WebP image with optional lossless encoding.
    public func toWebp(path: String, quality: Int = 80, lossless: Bool = false) throws {
        var options = SaveOptions()
        options.format = .webp
        options.quality = quality
        options.lossless = lossless
        try toFile(path, options: options)
    }
}
