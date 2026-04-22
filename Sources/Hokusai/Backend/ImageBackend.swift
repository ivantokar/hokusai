import Foundation

/// PURPOSE: Protocol defining the common interface for image processing backends
protocol ImageBackend {
    /// PURPOSE: Load image from file path
    static func loadFromFile(_ path: String) throws -> Self

    /// PURPOSE: Load image from data buffer
    static func loadFromBuffer(_ data: Data) throws -> Self

    /// PURPOSE: Save image to file
    func saveToFile(_ path: String, format: String?, quality: Int?) throws

    /// PURPOSE: Convert image to data buffer
    func toBuffer(format: String?, quality: Int?) throws -> Data

    /// PURPOSE: Get image width
    func getWidth() throws -> Int

    /// PURPOSE: Get image height
    func getHeight() throws -> Int

    /// PURPOSE: Get number of bands (channels)
    func getBands() throws -> Int

    /// PURPOSE: Check if image has alpha channel
    func hasAlpha() throws -> Bool
}

/// PURPOSE: Backend type identifier
enum BackendType {
    case vips    // libvips - fast, streaming, memory-efficient
}
