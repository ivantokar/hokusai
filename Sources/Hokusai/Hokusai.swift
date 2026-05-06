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

    /// Asynchronously load an image from a filesystem path.
    ///
    /// - Parameters:
    ///   - path: Path to a readable image file.
    ///   - options: Load options, including the libvips access mode.
    ///     Defaults to random (full decode). Pass ``LoadOptions/sequential``
    ///     for lower peak memory on large single-pass pipelines.
    public static func image(from path: String, options: LoadOptions = LoadOptions()) async throws -> HokusaiImage {
        return try loadFromFile(path, options: options)
    }

    /// Asynchronously load an image from in-memory bytes.
    ///
    /// - Parameters:
    ///   - data: Encoded image bytes (JPEG, PNG, WebP, etc.).
    ///   - options: Load options, including the libvips access mode.
    public static func image(from data: Data, options: LoadOptions = LoadOptions()) async throws -> HokusaiImage {
        return try loadFromBuffer(data, options: options)
    }

    /// Synchronous load from file for non-async call sites.
    ///
    /// - Parameters:
    ///   - path: Path to a readable image file.
    ///   - options: Load options. Defaults to random access.
    public static func loadFromFile(_ path: String, options: LoadOptions = LoadOptions()) throws -> HokusaiImage {
        let vipsBackend = try VipsBackend.loadFromFile(path, options: options)
        return HokusaiImage(backend: .vips(vipsBackend))
    }

    /// Synchronous load from encoded bytes for non-async call sites.
    ///
    /// - Parameters:
    ///   - data: Encoded image bytes.
    ///   - options: Load options. Defaults to random access.
    public static func loadFromBuffer(_ data: Data, options: LoadOptions = LoadOptions()) throws -> HokusaiImage {
        let vipsBackend = try VipsBackend.loadFromBuffer(data, options: options)
        return HokusaiImage(backend: .vips(vipsBackend))
    }

    // MARK: - Thumbnail

    /// Load and resize a file in a single optimised libvips pass.
    ///
    /// Calls `vips_thumbnail()` internally, which reads only enough of the
    /// source file to produce the output size. For JPEG sources libvips shrinks
    /// inside the JPEG decoder (by 2×, 4×, or 8×), so the convolution kernel
    /// operates on a much smaller intermediate image. For TIFF and HEIF there
    /// are similar optimisations. For PNG and most WebP there is no
    /// shrink-on-load and performance is similar to ``loadFromFile(_:options:)``
    /// followed by ``HokusaiImage/resize(width:height:options:)``.
    ///
    /// EXIF auto-rotation is applied by default. Pass
    /// `options.noRotate = true` to disable it.
    ///
    /// Prefer ``HokusaiImage/resize(width:height:options:)`` when you need an
    /// explicit interpolation kernel or fit modes like ``ResizeFit/contain``.
    ///
    /// - Parameters:
    ///   - path: Path to a readable image file.
    ///   - width: Target width. Output height is determined by the source
    ///     aspect ratio unless `options.height` is also set.
    ///   - options: Thumbnail options (height constraint, crop strategy,
    ///     rotation behaviour).
    /// - Returns: A new ``HokusaiImage`` at the requested dimensions.
    public static func thumbnail(from path: String, width: Int, options: ThumbnailOptions = ThumbnailOptions()) throws -> HokusaiImage {
        let backend = try VipsBackend.thumbnailFromFile(path, width: width, options: options)
        return HokusaiImage(backend: .vips(backend))
    }

    /// Load and resize an in-memory buffer in a single optimised libvips pass.
    ///
    /// Calls `vips_thumbnail_buffer()` internally. Behaviour and trade-offs
    /// are the same as ``thumbnail(from:width:options:)``; shrink-on-load
    /// applies for formats that support it in buffer form.
    ///
    /// - Parameters:
    ///   - data: Encoded image bytes.
    ///   - width: Target width.
    ///   - options: Thumbnail options.
    /// - Returns: A new ``HokusaiImage`` at the requested dimensions.
    public static func thumbnail(from data: Data, width: Int, options: ThumbnailOptions = ThumbnailOptions()) throws -> HokusaiImage {
        let backend = try VipsBackend.thumbnailFromBuffer(data, width: width, options: options)
        return HokusaiImage(backend: .vips(backend))
    }

    // MARK: - Version Information

    /// PURPOSE: Return runtime libvips version string.
    public static var vipsVersion: String {
        return VipsBackend.version
    }

    /// PURPOSE: Legacy ImageMagick version shim kept for API compatibility.
    @available(*, deprecated, message: "ImageMagick backend was removed. Use vipsVersion instead.")
    public static var magickVersion: String {
        return "removed (libvips-only)"
    }

    /// PURPOSE: Get combined version string
    public static var version: String {
        return "Hokusai (libvips \(vipsVersion))"
    }

    /// PURPOSE: Get or set the libvips global thread concurrency.
    /// Setting to 0 restores the libvips default (number of CPU cores).
    public static var vipsConcurrency: Int {
        get { VipsBackend.concurrency }
        set { VipsBackend.concurrency = newValue }
    }
}
