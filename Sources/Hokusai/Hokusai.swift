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

    /// Initialize the libvips runtime.
    ///
    /// Idempotent and thread-safe: repeated and concurrent calls are safe,
    /// and only the first successful call performs work. All image-loading
    /// entry points initialize the runtime automatically, so an explicit call
    /// is only needed when you want initialization failures surfaced at
    /// application startup.
    ///
    /// - Throws: ``HokusaiError/initializationFailed(_:)`` if libvips could
    ///   not be initialized, or if ``shutdown()`` has already been called
    ///   (libvips cannot be restarted within the same process).
    public static func initialize() throws {
        try VipsBackend.initialize()
    }

    /// Permanently shut down the libvips runtime.
    ///
    /// This is an advanced, final process-teardown operation — not part of
    /// the ordinary application lifecycle. Long-running applications such as
    /// servers should never call it; the operating system reclaims libvips
    /// resources at process exit. Call it, at most once, immediately before
    /// process exit (for example, to produce clean leak-checker reports), and
    /// only after every `HokusaiImage` has been released — shutting down while
    /// images are still alive is undefined behaviour in libvips.
    ///
    /// After `shutdown()` the runtime cannot be re-initialized: subsequent
    /// loads throw ``HokusaiError/initializationFailed(_:)``. Repeated calls
    /// are no-ops.
    public static func shutdown() {
        VipsBackend.shutdown()
    }

    // MARK: - Image Loading

    /// Load an image from a filesystem path.
    ///
    /// This performs synchronous libvips work on the calling thread. (Earlier
    /// versions declared this method `async` although it never suspended; the
    /// marker was removed so callers are not misled about execution. The
    /// upcoming pipeline-API milestone will define the library's terminal
    /// execution and concurrency policy; until then, offload to a background
    /// executor yourself if you must not block the caller.)
    ///
    /// - Parameters:
    ///   - path: Path to a readable image file.
    ///   - options: Load options, including the libvips access-pattern hint.
    ///     Defaults to random access. See ``AccessMode`` for the trade-offs.
    public static func image(from path: String, options: LoadOptions = LoadOptions()) throws -> HokusaiImage {
        return try loadFromFile(path, options: options)
    }

    /// Load an image from in-memory bytes.
    ///
    /// The bytes are copied during the call, so `data` does not need to
    /// outlive the returned image. Like the path-based overload, this is
    /// synchronous libvips work on the calling thread.
    ///
    /// - Parameters:
    ///   - data: Encoded image bytes (JPEG, PNG, WebP, etc.).
    ///   - options: Load options, including the libvips access-pattern hint.
    public static func image(from data: Data, options: LoadOptions = LoadOptions()) throws -> HokusaiImage {
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
    /// Calls `vips_thumbnail()` internally, which uses the shrink-on-load
    /// support of the format loader where one exists: JPEG (decoder shrink by
    /// 2×, 4×, or 8×), WebP (libwebp decode-time scaling), TIFF (pyramid
    /// levels), HEIF (embedded thumbnail), PDF/SVG (render scale). PNG has no
    /// shrink-on-load, so PNG performance is similar to
    /// ``loadFromFile(_:options:)`` followed by
    /// ``HokusaiImage/resize(width:height:options:)``.
    ///
    /// Sources smaller than the target are scaled **up** by default (libvips
    /// `VIPS_SIZE_BOTH` behaviour). EXIF auto-rotation is applied by default;
    /// pass `options.noRotate = true` to disable it.
    ///
    /// Prefer ``HokusaiImage/resize(width:height:options:)`` when you need an
    /// explicit interpolation kernel or fit modes like ``ResizeFit/contain``.
    ///
    /// - Parameters:
    ///   - path: Path to a readable image file.
    ///   - width: Target width (1...Int32.max). Output height follows the
    ///     source aspect ratio unless `options.height` is also set.
    ///   - options: Thumbnail options (height constraint, crop strategy,
    ///     rotation behaviour). Crop strategies other than
    ///     ``ThumbnailCrop/none`` require `options.height`.
    /// - Returns: A new ``HokusaiImage`` at the requested dimensions.
    /// - Throws: ``HokusaiError/invalidDimensions(_:)`` for non-positive or
    ///   out-of-range dimensions, ``HokusaiError/fileNotFound(_:)``, or
    ///   ``HokusaiError/loadFailed(_:)`` when libvips cannot decode or
    ///   transform the source.
    public static func thumbnail(from path: String, width: Int, options: ThumbnailOptions = ThumbnailOptions()) throws -> HokusaiImage {
        let backend = try VipsBackend.thumbnailFromFile(path, width: width, options: options)
        return HokusaiImage(backend: .vips(backend))
    }

    /// Load and resize an in-memory buffer in a single optimised libvips pass.
    ///
    /// Behaviour, validation, and trade-offs are the same as the path-based
    /// `thumbnail`; shrink-on-load applies for formats that support it in
    /// buffer form. The bytes are copied during the call, so `data` does not
    /// need to outlive the returned image.
    ///
    /// - Parameters:
    ///   - data: Encoded image bytes.
    ///   - width: Target width (1...Int32.max).
    ///   - options: Thumbnail options. Crop strategies other than
    ///     ``ThumbnailCrop/none`` require `options.height`.
    /// - Returns: A new ``HokusaiImage`` at the requested dimensions.
    /// - Throws: ``HokusaiError/invalidDimensions(_:)``,
    ///   ``HokusaiError/invalidImageData`` for empty input, or
    ///   ``HokusaiError/loadFailed(_:)`` when libvips cannot decode or
    ///   transform the source.
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
