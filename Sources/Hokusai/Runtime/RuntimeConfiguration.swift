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
///     vipsConcurrency: .fixed(2)
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

    public init(
        maxConcurrentEvaluations: ConcurrencyLimit = .automatic,
        maxQueuedEvaluations: Int? = nil,
        vipsConcurrency: ConcurrencyLimit = .automatic
    ) {
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
/// built, not on Hokusai's package dependencies. AVIF encoding is verified by
/// encoding a tiny image, because a HEIF saver can exist without an AV1
/// encoder.
public struct RuntimeCapabilities: Sendable, Hashable {
    /// The linked libvips version, for example `8.18.5`.
    public let libvipsVersion: String

    /// Formats the linked libvips can decode.
    public let inputFormats: Set<ImageFormat>

    /// Formats Hokusai's typed encoders can produce with this build.
    ///
    /// PDF output uses Cairo and is independent of PDF input support.
    public let outputFormats: Set<ImageFormat>

    /// Whether `drawText` can render text (libvips built with Pango/Cairo).
    public let textRendering: Bool

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
