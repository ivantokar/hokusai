import Foundation

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
///   cached window cannot be satisfied and fail with a libvips error — there
///   is no silent fallback to random access. Operations that need out-of-order
///   pixel access (rotation by non-90° angles, flips, smart crop, some
///   compositing) are therefore unsafe in this mode.
///
/// ## Practical guidance
///
/// - Neither mode changes *what* is decoded, only how the decode is buffered.
///   In particular, downscaling a JPEG via `resize` fully decodes the source
///   in both modes; only the `thumbnail` entry points engage the decoders'
///   shrink-on-load support.
/// - Prefer ``Hokusai/thumbnail(from:width:options:)`` when the goal is a
///   smaller output from a large JPEG/WebP/TIFF/HEIF source.
/// - Use sequential access only when you have measured that peak memory is a
///   problem and the pipeline is genuinely single-pass and top-to-bottom.
///   In our benchmarks, sequential access made heavily downscaled JPEG
///   pipelines significantly slower than the default.
public enum AccessMode: Sendable {
    /// Pixels may be read in any order. Safe for all operations. Non-seekable
    /// formats are fully decoded (to memory or disk temp) on first access.
    case random
    /// Forward-only streaming decode with a small line window. Lower peak
    /// memory for linear pipelines; operations that need out-of-order pixel
    /// access fail with a libvips error.
    case sequential
}

/// Options controlling how Hokusai loads an image from disk or memory.
public struct LoadOptions: Sendable {
    /// The libvips access-pattern hint to use when decoding the source image.
    public var access: AccessMode

    public init(access: AccessMode = .random) {
        self.access = access
    }

    /// Convenience preset for sequential (streaming) loading.
    public static let sequential = LoadOptions(access: .sequential)
}
