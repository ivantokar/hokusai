import Foundation

/// PURPOSE: Main static API entry point for Hokusai image processing.
/// CONSTRAINTS:
/// - Initialize libvips exactly once during process startup.
/// - Do not instantiate this type directly.
/// AI HINTS:
/// - Keep this surface minimal and stable.
/// - Route all image loading through libvips-backed helpers.
public struct Hokusai {
    private init() {} // Prevent instantiation

    // MARK: - Lifecycle Management

    /// PURPOSE: Initialize libvips runtime for all future image operations.
    /// SIDE EFFECTS: Initializes global libvips state.
    /// DO NOT: Call repeatedly in hot paths.
    public static func initialize() throws {
        try VipsBackend.initialize()
    }

    /// PURPOSE: Shutdown libvips runtime during app teardown.
    /// SIDE EFFECTS: Releases global libvips resources.
    public static func shutdown() {
        VipsBackend.shutdown()
    }

    // MARK: - Image Loading

    /// PURPOSE: Asynchronously load an image from a filesystem path.
    /// INPUT: `path` must reference a readable image file.
    /// OUTPUT: `HokusaiImage` backed by libvips.
    ///
    /// Example:
    /// ```swift
    /// let image = try await Hokusai.image(from: "/path/to/photo.jpg")
    /// ```
    public static func image(from path: String) async throws -> HokusaiImage {
        return try loadFromFile(path)
    }

    /// PURPOSE: Asynchronously load an image from in-memory bytes.
    /// INPUT: `data` must contain a valid encoded image payload.
    /// OUTPUT: `HokusaiImage` backed by libvips.
    ///
    /// Example:
    /// ```swift
    /// let imageData = try Data(contentsOf: url)
    /// let image = try await Hokusai.image(from: imageData)
    /// ```
    public static func image(from data: Data) async throws -> HokusaiImage {
        return try loadFromBuffer(data)
    }

    /// PURPOSE: Synchronous load from file for non-async call sites.
    /// CONSTRAINTS: Uses libvips-only backend.
    public static func loadFromFile(_ path: String) throws -> HokusaiImage {
        // Load using VipsBackend (efficient for most operations)
        let vipsBackend = try VipsBackend.loadFromFile(path)
        return HokusaiImage(backend: .vips(vipsBackend))
    }

    /// PURPOSE: Synchronous load from encoded bytes for non-async call sites.
    /// CONSTRAINTS: Uses libvips-only backend.
    public static func loadFromBuffer(_ data: Data) throws -> HokusaiImage {
        // Load using VipsBackend (efficient for most operations)
        let vipsBackend = try VipsBackend.loadFromBuffer(data)
        return HokusaiImage(backend: .vips(vipsBackend))
    }

    // MARK: - Version Information

    /// PURPOSE: Return runtime libvips version string.
    public static var vipsVersion: String {
        return VipsBackend.version
    }

    /// Legacy ImageMagick version shim kept for API compatibility.
    @available(*, deprecated, message: "ImageMagick backend was removed. Use vipsVersion instead.")
    public static var magickVersion: String {
        return "removed (libvips-only)"
    }

    /// Get combined version string
    public static var version: String {
        return "Hokusai (libvips \(vipsVersion))"
    }
}
