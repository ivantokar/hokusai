import Foundation

/// Internal contract implemented by an image-processing backend.
///
/// The legacy API delegates decoding, encoding, and pixel inspection through
/// this narrow surface so public code never depends on a native backend type.
protocol ImageBackend {
    /// Decodes an image from a local path using the supplied loading options.
    static func loadFromFile(_ path: String, options: LoadOptions) throws -> Self

    /// Decodes an image from an owned data buffer using the supplied options.
    static func loadFromBuffer(_ data: Data, options: LoadOptions) throws -> Self

    /// Encodes the image and writes it to a local file.
    func saveToFile(_ path: String, format: String?, quality: Int?) throws

    /// Encodes the image into an in-memory data buffer.
    func toBuffer(format: String?, quality: Int?) throws -> Data

    /// Returns the current width in pixels.
    func getWidth() throws -> Int

    /// Returns the current height in pixels.
    func getHeight() throws -> Int

    /// Returns the current number of pixel bands (channels).
    func getBands() throws -> Int

    /// Reports whether the current image contains an alpha channel.
    func hasAlpha() throws -> Bool
}

/// Internal backend identifier kept for legacy compatibility.
enum BackendType {
    /// libvips provides streaming, memory-efficient image evaluation.
    case vips
}
