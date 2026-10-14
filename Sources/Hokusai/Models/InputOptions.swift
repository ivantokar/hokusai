import Foundation

/// How Hokusai opens an encoded image from `Data` or a local file.
///
/// `InputOptions` is the single policy for decoding a source. Opening is lazy:
/// constructing a pipeline records the source and these options; the file is
/// read (or the bytes are copied into native storage) when a terminal method
/// evaluates the pipeline. `Data` is retained copy-on-write until then, so
/// callers may mutate or release their own value immediately.
///
/// ```swift
/// let image = try Hokusai(
///     data: upload,
///     options: .init(
///         failOn: .truncated,
///         limits: .init(maxBytes: 20_000_000, maxPixels: 50_000_000)
///     )
/// )
/// ```
public struct InputOptions: Sendable, Equatable {
    /// How libvips may order pixel reads. ``AccessMode/random`` is the safe default.
    public var access: AccessMode

    /// When decoder problems become errors. Defaults to ``DecodeFailureLevel/warning``.
    public var failOn: DecodeFailureLevel

    /// Zero-based page to load from a multi-page source such as a TIFF or PDF.
    ///
    /// `nil` loads the first page. Exactly one page is ever loaded; page
    /// ranges, all-page loading, and animation are not supported yet.
    public var page: Int?

    /// Defensive limits checked before expensive pixel evaluation.
    public var limits: InputLimits

    /// Bypass libvips' operation cache when opening a local file, so changes
    /// to a file at the same path are seen. Defaults to `false`. Has no
    /// effect for `Data` sources, and Hokusai keeps no cache of its own.
    public var revalidate: Bool

    public init(
        access: AccessMode = .random,
        failOn: DecodeFailureLevel = .warning,
        page: Int? = nil,
        limits: InputLimits = InputLimits(),
        revalidate: Bool = false
    ) {
        self.access = access
        self.failOn = failOn
        self.page = page
        self.limits = limits
        self.revalidate = revalidate
    }

    /// Streaming input with otherwise default options. See ``AccessMode/sequential``.
    public static let sequential = InputOptions(access: .sequential)

    /// Rejects values that cannot be applied, before any source is touched.
    func validate() throws {
        if let page, page < 0 {
            throw HokusaiError.invalidOption(name: "page", reason: "must be zero or greater")
        }
        try limits.validate()
    }
}

/// Access-pattern hint for libvips image loading.
///
/// libvips loads images lazily in both modes: opening an image reads only the
/// header (dimensions, bands, metadata), and pixels are decoded on first
/// access. The access mode is a *hint* telling libvips in which order the
/// pipeline will request pixels, which changes how the decode is managed:
///
/// - ``random``: The default. Pixels may be requested in any order. For
///   formats whose decoders cannot seek (JPEG, PNG, WebP, ...), libvips
///   decodes the whole image on first pixel access — into a memory buffer for
///   smaller images or a temporary disk file for larger ones (controlled by
///   libvips' `vips-disc-threshold`, 100 MB by default). Formats with native
///   random-access layouts (tiled TIFF, FITS, OpenSlide, VIPS `.v`) are read
///   directly without a full decode.
///
/// - ``sequential``: Pixels are requested strictly top-to-bottom. libvips
///   streams the decode and keeps only a small window of recent scanlines in
///   memory, which lowers peak memory for large sources in single-pass
///   pipelines (e.g. load → resize → save). Requests *ahead* of the current
///   read position are satisfied by decoding forward; requests *behind* the
///   cached window cannot be satisfied and fail — there is no silent fallback
///   to random access. Operations that need out-of-order pixel access
///   (rotation by non-90° angles, flips, smart crop, some compositing) may
///   therefore fail in this mode. Because the failure comes from reading the
///   source, it is reported as ``HokusaiError/decode(_:)``.
///
/// ## Practical guidance
///
/// - Neither mode changes *what* is decoded, only how the decode is buffered.
///   Downscaling a JPEG via `resize` fully decodes the source in both modes.
/// - Use sequential access only when you have measured that peak memory is a
///   problem and the pipeline is genuinely single-pass and top-to-bottom.
///   In our benchmarks, sequential access made heavily downscaled JPEG
///   pipelines significantly slower than the default.
public enum AccessMode: Sendable {
    /// Pixels may be read in any order. Safe for all operations.
    case random
    /// Forward-only streaming decode with a small line window. Lower peak
    /// memory for linear pipelines; operations that need out-of-order pixel
    /// access fail.
    case sequential
}

/// When a decoder problem becomes an error.
///
/// Levels are cumulative, from most permissive to strictest. A source that is
/// rejected fails with ``HokusaiError/decode(_:)`` when the pipeline is
/// evaluated, because decoders report most problems only while reading pixels.
public enum DecodeFailureLevel: Sendable, Equatable {
    /// Never fail on decoder problems; decode as much as possible.
    case none
    /// Fail when the source is truncated.
    case truncated
    /// Fail on truncation and on decoder errors.
    case error
    /// Fail on truncation, errors, and decoder warnings. The default, and the
    /// most likely to reject slightly malformed but viewable images.
    case warning
}

/// Defensive bounds on an input, checked before expensive pixel evaluation.
///
/// Exceeding a limit fails with ``HokusaiError/resource(_:)``. The defaults are
/// sized to stop decompression bombs while accepting ordinary photographs;
/// servers should tighten them to their own upload policy. Native codec safety
/// limits stay in force regardless of these values.
public struct InputLimits: Sendable, Equatable {
    /// Default for ``maxBytes``: 512 MiB of encoded data.
    public static let defaultMaxBytes = 512 * 1024 * 1024

    /// Default for ``maxPixels``: 268,402,689 (16383 × 16383).
    public static let defaultMaxPixels = 268_402_689

    /// Default for ``maxChannels``: 8 bands (RGB or CMYK plus alpha and spare).
    public static let defaultMaxChannels = 8

    /// Largest encoded source accepted, in bytes. Checked before `Data` is
    /// copied into native storage and against a local file's size.
    public var maxBytes: Int

    /// Largest decoded image accepted, as width × height of the loaded page.
    public var maxPixels: Int

    /// Largest number of bands (channels) accepted.
    public var maxChannels: Int

    public init(
        maxBytes: Int = InputLimits.defaultMaxBytes,
        maxPixels: Int = InputLimits.defaultMaxPixels,
        maxChannels: Int = InputLimits.defaultMaxChannels
    ) {
        self.maxBytes = maxBytes
        self.maxPixels = maxPixels
        self.maxChannels = maxChannels
    }

    func validate() throws {
        for (name, value) in [("limits.maxBytes", maxBytes), ("limits.maxPixels", maxPixels), ("limits.maxChannels", maxChannels)] where value < 1 {
            throw HokusaiError.invalidOption(name: name, reason: "must be at least 1")
        }
    }

    /// Throws if `byteCount` encoded bytes exceed ``maxBytes``.
    func checkEncodedBytes(_ byteCount: Int) throws {
        guard byteCount <= maxBytes else {
            throw HokusaiError.resource(ResourceFailure(
                kind: .encodedBytes, limit: maxBytes, actual: byteCount,
                reason: "the encoded image is larger than the allowed \(maxBytes) bytes"))
        }
    }

    /// Throws if an image of this shape exceeds ``maxPixels`` or ``maxChannels``.
    ///
    /// The pixel count is computed with overflow detection, so absurd header
    /// dimensions are rejected rather than wrapping around.
    func checkDecoded(width: Int, height: Int, channels: Int) throws {
        let (pixels, overflowed) = width.multipliedReportingOverflow(by: height)
        if overflowed || pixels > maxPixels {
            throw HokusaiError.resource(ResourceFailure(
                kind: .decodedPixels, limit: maxPixels, actual: overflowed ? nil : pixels,
                reason: "a \(width)×\(height) image exceeds the allowed \(maxPixels) pixels"))
        }
        guard channels <= maxChannels else {
            throw HokusaiError.resource(ResourceFailure(
                kind: .channels, limit: maxChannels, actual: channels,
                reason: "the image has \(channels) channels; at most \(maxChannels) are allowed"))
        }
    }
}
