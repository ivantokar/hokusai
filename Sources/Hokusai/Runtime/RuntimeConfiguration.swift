import Foundation

/// Process-wide runtime settings, applied once at application startup.
///
/// Configuration freezes at the first runtime use: ``Hokusai/initialize()``,
/// ``Hokusai/capabilities()``, or the first terminal evaluation. Building a
/// pipeline does not freeze it. ``Hokusai/configure(_:)`` may be called once,
/// before that point.
///
/// ```swift
/// try Hokusai.configure(.init(
///     maxConcurrentEvaluations: .fixed(4),
///     maxQueuedEvaluations: 64,
///     vipsConcurrency: .fixed(2),
///     maxOutputPixels: 100_000_000
/// ))
/// ```
public struct RuntimeConfiguration: Sendable, Hashable {
    /// How many terminal evaluations (`data()`, `write(to:)`) may run at once.
    ///
    /// This bounds Hokusai's admission of whole pipelines, which governs memory
    /// and latency. It is independent of ``vipsConcurrency``: one evaluation
    /// can itself use many libvips worker threads. `.automatic` currently
    /// uses the number of active processors; the value will be chosen from
    /// benchmarks before the major release.
    public var maxConcurrentEvaluations: ConcurrencyLimit

    /// How many evaluations may wait for a slot before new ones are rejected
    /// with ``HokusaiError/resource(_:)`` (kind `.queuedEvaluations`). `nil` queues without bound.
    ///
    /// Waiting evaluations retain their source bytes, so a bound protects
    /// memory under overload. Applications that apply backpressure upstream
    /// can leave this `nil`.
    public var maxQueuedEvaluations: Int?

    /// libvips' process-wide worker-thread count per image computation.
    /// `.automatic` keeps libvips' own default.
    public var vipsConcurrency: ConcurrencyLimit

    /// Refuses to run the libvips loaders that parse complex or
    /// attacker-influenced formats: PDF (poppler), SVG, ImageMagick and
    /// OpenSlide. Defaults to `false`.
    ///
    /// Turn this on for services that decode uploads from untrusted users. A
    /// source in a blocked format then fails as ``HokusaiError/decode(_:)``, and
    /// ``RuntimeCapabilities/blockedInputFormats`` lists what was turned off.
    /// PDF *output* is Cairo and is unaffected. JPEG, PNG, WebP, GIF, TIFF and
    /// HEIF loaders are not marked untrusted by libvips.
    public var blockUntrustedOperations: Bool

    /// Default for ``maxOutputPixels``: 1,073,741,824 (2^30) pixels.
    public static let defaultMaxOutputPixels = 1_073_741_824

    /// The most pixels any image a pipeline produces may have, final or
    /// intermediate, as width × height. A pipeline that would exceed it fails
    /// with ``HokusaiError/resource(_:)`` (kind `.outputPixels`) while it is being
    /// planned, before any pixel is computed.
    ///
    /// ``InputLimits`` only judge the source. Without this a request that
    /// controls a size, such as `resize(width: 10_000_000)`, would occupy an
    /// evaluation slot for as long as the work takes. The default only refuses
    /// sizes no real canvas has; a service should set it to its own policy.
    /// `nil` removes the bound.
    public var maxOutputPixels: Int?

    public init(
        maxConcurrentEvaluations: ConcurrencyLimit = .automatic,
        maxQueuedEvaluations: Int? = nil,
        vipsConcurrency: ConcurrencyLimit = .automatic,
        blockUntrustedOperations: Bool = false,
        maxOutputPixels: Int? = RuntimeConfiguration.defaultMaxOutputPixels
    ) {
        self.maxOutputPixels = maxOutputPixels
        self.blockUntrustedOperations = blockUntrustedOperations
        self.maxConcurrentEvaluations = maxConcurrentEvaluations
        self.maxQueuedEvaluations = maxQueuedEvaluations
        self.vipsConcurrency = vipsConcurrency
    }

    /// Rejects values that cannot be applied, before any state changes.
    func validate() throws {
        if let value = maxConcurrentEvaluations.fixedValue, value < 1 {
            throw HokusaiError.invalidOption(name: "maxConcurrentEvaluations", reason: "must be at least 1")
        }
        if let value = maxQueuedEvaluations, value < 0 {
            throw HokusaiError.invalidOption(name: "maxQueuedEvaluations", reason: "must be zero or greater")
        }
        if let value = maxOutputPixels, value < 1 {
            throw HokusaiError.invalidOption(name: "maxOutputPixels", reason: "must be at least 1")
        }
        if let value = vipsConcurrency.fixedValue, value < 1 || Int32(exactly: value) == nil {
            throw HokusaiError.invalidOption(name: "vipsConcurrency", reason: "must be in 1...\(Int32.max)")
        }
    }
}

/// A concurrency setting that is either chosen automatically or fixed.
public struct ConcurrencyLimit: Sendable, Hashable, CustomStringConvertible {
    /// The fixed value, or `nil` when chosen automatically.
    public let fixedValue: Int?

    /// Let Hokusai or libvips choose the value.
    public static let automatic = ConcurrencyLimit(fixedValue: nil)

    /// Use exactly `value`.
    public static func fixed(_ value: Int) -> ConcurrencyLimit {
        ConcurrencyLimit(fixedValue: value)
    }

    public var description: String {
        fixedValue.map(String.init) ?? "automatic"
    }
}

/// Image capabilities of the linked native libraries.
///
/// Codec availability depends on how libvips (and its codec libraries) were
/// built, not on Hokusai's package dependencies. Reading and writing are
/// reported independently: AVIF encoding is verified by encoding a tiny image
/// and AVIF decoding by decoding a small embedded one, because a HEIF saver can
/// exist without an AV1 encoder and a HEIF loader without an AV1 decoder.
public struct RuntimeCapabilities: Sendable, Hashable {
    /// The linked libvips version, for example `8.18.5`.
    public let libvipsVersion: String

    /// The linked Cairo version, for example `1.18.0`. Cairo writes PDF output;
    /// it is independent of libvips.
    public let cairoVersion: String

    /// Formats the linked libvips can decode and is allowed to.
    public let inputFormats: Set<ImageFormat>

    /// Formats this build can decode but that are switched off by
    /// ``RuntimeConfiguration/blockUntrustedOperations``. Absent and blocked
    /// are different problems: a blocked format is a deployment choice, an
    /// absent one needs a different libvips build.
    public let blockedInputFormats: Set<ImageFormat>

    /// Formats Hokusai's typed encoders can produce with this build.
    ///
    /// PDF output uses Cairo and is independent of PDF input support.
    public let outputFormats: Set<ImageFormat>

    /// Whether `drawText` can render text (libvips built with Pango/Cairo).
    public let textRendering: Bool

    /// The HEIF codecs this build can encode. `.av1` is what AVIF output
    /// needs; `.hevc` is what `.heic` output needs and is often missing.
    /// Decoding is reported separately, through ``canDecode(_:)``.
    public let heifCompressions: Set<HEIFCompression>

    /// Whether palette (indexed) PNG output works. It needs libimagequant or
    /// quantizr; without them libvips would silently write full colour.
    public let pngPalette: Bool

    /// Whether the HEIF encoder can use `compression`.
    public func canEncode(_ compression: HEIFCompression) -> Bool { heifCompressions.contains(compression) }

    init(
        libvipsVersion: String, cairoVersion: String = "unknown", inputFormats: Set<ImageFormat>, outputFormats: Set<ImageFormat>,
        blockedInputFormats: Set<ImageFormat> = [],
        textRendering: Bool, heifCompressions: Set<HEIFCompression> = [], pngPalette: Bool = false
    ) {
        self.cairoVersion = cairoVersion
        self.blockedInputFormats = blockedInputFormats
        self.libvipsVersion = libvipsVersion
        self.inputFormats = inputFormats
        self.outputFormats = outputFormats
        self.textRendering = textRendering
        self.heifCompressions = heifCompressions
        self.pngPalette = pngPalette
    }

    /// Whether `format` can be decoded.
    public func canDecode(_ format: ImageFormat) -> Bool { inputFormats.contains(format) }

    /// Whether Hokusai can encode `format` with this build.
    public func canEncode(_ format: ImageFormat) -> Bool { outputFormats.contains(format) }
}

/// A snapshot of Hokusai's process-level runtime state.
///
/// Counters describe Hokusai's evaluation scheduler. They do not measure
/// libvips' internal worker threads or memory used by codec libraries.
public struct RuntimeStatus: Sendable, Hashable {
    /// The configuration in effect, or the one that will take effect when the
    /// runtime is first used.
    public let configuration: RuntimeConfiguration

    /// Whether the configuration can no longer be changed.
    public let isConfigurationFrozen: Bool

    /// Evaluations waiting for a slot.
    public let queuedEvaluations: Int

    /// Evaluations currently holding a slot.
    public let activeEvaluations: Int

    /// The effective admission limit.
    public let maxConcurrentEvaluations: Int

    /// libvips' effective worker concurrency, or `nil` before libvips has
    /// been initialized.
    public let vipsConcurrency: Int?
}
