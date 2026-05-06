import Foundation

/// Access mode for libvips image loading.
///
/// libvips supports two access patterns that trade memory for capability:
///
/// - ``random``: The default. The full image is available in memory and any
///   pixel can be read at any time. Required for operations like rotation,
///   smartcrop, and compositing.
///
/// - ``sequential``: The image is decoded as a forward-only stream. libvips
///   holds only a small window of rows in memory at once. Useful when you
///   are doing a single-pass pipeline (e.g., load -> resize -> save to buffer)
///   on a large source file and want to reduce peak memory. Not safe for
///   operations that need random access.
///
/// ## When sequential access can help
///
/// Sequential access lowers peak RSS for large source files processed in a
/// linear pipeline. The time savings come mainly from reduced page faults and
/// memory pressure under load, not from reduced decode work.
///
/// For JPEG, TIFF, and HEIF sources where shrink-on-load is the goal,
/// prefer ``Hokusai/thumbnail(from:width:options:)`` instead — it combines
/// optimised load and resize in a single libvips call without requiring you
/// to choose an access mode.
///
/// ## When sequential access may not help
///
/// - Small images: the overhead of tracking the sequential cursor can exceed
///   any memory savings.
/// - Operations that require random access (rotation by non-90° multiples,
///   compositing with an offset, some crop strategies). libvips will error
///   or silently fall back to random access in those cases.
/// - Pipelines that read the image more than once (e.g., computing metadata
///   after resize). Each read reopens the source.
public enum AccessMode: Sendable {
    /// Full decode; any pixel readable at any time. Safe for all operations.
    case random
    /// Forward-only streaming decode. Lower peak memory for linear pipelines.
    /// Not safe for operations that require random pixel access.
    case sequential
}

/// Options controlling how Hokusai loads an image from disk or memory.
public struct LoadOptions: Sendable {
    /// The libvips access mode to use when decoding the source image.
    public var access: AccessMode

    public init(access: AccessMode = .random) {
        self.access = access
    }

    /// Convenience preset for sequential (streaming) loading.
    public static let sequential = LoadOptions(access: .sequential)
}
