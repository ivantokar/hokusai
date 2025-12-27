import Foundation

/// Protocol defining the common interface for image processing backends
protocol ImageBackend {
    /// Load image from file path
    static func loadFromFile(_ path: String) throws -> Self

    /// Load image from data buffer
    static func loadFromBuffer(_ data: Data) throws -> Self

    /// Save image to file
    func saveToFile(_ path: String, format: String?, quality: Int?) throws

    /// Convert image to data buffer
    func toBuffer(format: String?, quality: Int?) throws -> Data

    /// Get image width
    func getWidth() throws -> Int

    /// Get image height
    func getHeight() throws -> Int

    /// Get number of bands (channels)
    func getBands() throws -> Int

    /// Check if image has alpha channel
    func hasAlpha() throws -> Bool
}

/// Backend type identifier
enum BackendType {
    case vips    // libvips - fast, streaming, memory-efficient
    case magick  // ImageMagick - advanced text rendering, effects
}
