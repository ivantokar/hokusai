import Foundation

/// Main API entry point for Hokusai image processing
public struct Hokusai {
    private init() {} // Prevent instantiation

    // MARK: - Lifecycle Management

    /// Initialize both libvips and ImageMagick (call once at app startup)
    public static func initialize() throws {
        try VipsBackend.initialize()
        MagickBackend.initialize()
    }

    /// Shutdown both backends (call at app teardown)
    public static func shutdown() {
        VipsBackend.shutdown()
        MagickBackend.shutdown()
    }

    // MARK: - Image Loading

    /// Load image from file path (uses libvips backend by default)
    ///
    /// Example:
    /// ```swift
    /// let image = try await Hokusai.image(from: "/path/to/photo.jpg")
    /// ```
    public static func image(from path: String) async throws -> HokusaiImage {
        return try loadFromFile(path)
    }

    /// Load image from data buffer (uses libvips backend by default)
    ///
    /// Example:
    /// ```swift
    /// let imageData = try Data(contentsOf: url)
    /// let image = try await Hokusai.image(from: imageData)
    /// ```
    public static func image(from data: Data) async throws -> HokusaiImage {
        return try loadFromBuffer(data)
    }

    /// Synchronous load from file
    public static func loadFromFile(_ path: String) throws -> HokusaiImage {
        // Load using VipsBackend (efficient for most operations)
        let vipsBackend = try VipsBackend.loadFromFile(path)
        return HokusaiImage(backend: .vips(vipsBackend))
    }

    /// Synchronous load from buffer
    public static func loadFromBuffer(_ data: Data) throws -> HokusaiImage {
        // Load using VipsBackend (efficient for most operations)
        let vipsBackend = try VipsBackend.loadFromBuffer(data)
        return HokusaiImage(backend: .vips(vipsBackend))
    }

    // MARK: - Version Information

    /// Get libvips version
    public static var vipsVersion: String {
        return VipsBackend.version
    }

    /// Get ImageMagick version
    public static var magickVersion: String {
        return MagickBackend.version
    }

    /// Get combined version string
    public static var version: String {
        return "Hokusai (libvips \(vipsVersion), ImageMagick \(magickVersion))"
    }
}
