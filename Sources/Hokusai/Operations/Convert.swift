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
        try native().write(to: path, options: options)
    }

    /// Encodes this legacy image into an owned data buffer.
    ///
    /// Buffers have no filename, so callers must select `options.format`.
    public func toBuffer(options: SaveOptions = SaveOptions()) throws -> Data {
        try native().encoded(options: options)
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
