import Foundation
import CVips

/// Process-scoped libvips runtime and its frozen configuration.
///
/// libvips is initialized at most once and stays available for the lifetime of
/// the process. Hokusai never calls `vips_shutdown()`: libvips documents it as
/// optional, and the runtime cannot be initialized again afterwards.
enum VipsRuntime {
    // MARK: - Configuration

    // Guarded by `lock`, which makes the `nonisolated(unsafe)` sound.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var configuration = ConfigurationState()
    nonisolated(unsafe) private static var initialized = false

    /// Records the startup configuration. Valid once, before first use.
    static func configure(_ requested: RuntimeConfiguration) throws {
        try requested.validate()
        try lock.withLock { try configuration.configure(requested) }
    }

    /// Freezes and returns the configuration in effect for this process.
    static func frozenConfiguration() -> RuntimeConfiguration {
        lock.withLock { configuration.freeze() }
    }

    /// The configuration without freezing it.
    static var configurationSnapshot: (configuration: RuntimeConfiguration, isFrozen: Bool, isInitialized: Bool) {
        lock.withLock { (configuration.effective, configuration.isFrozen, initialized) }
    }

    // MARK: - Initialization

    /// Swift lazily evaluates static stored properties exactly once, even under
    /// concurrent first use. A failure is cached: a process whose libvips
    /// failed to start stays unusable.
    private static let initialization: Result<Void, HokusaiError> = {
        let configuration = frozenConfiguration()
        guard vips_init("Hokusai") == 0 else {
            return .failure(.runtime(.native("initialize libvips", "libvips could not be initialized")))
        }
        if let threads = configuration.vipsConcurrency.fixedValue {
            swift_vips_concurrency_set(Int32(threads))
        }
        lock.withLock { initialized = true }
        return .success(())
    }()

    /// Ensures libvips has been initialized for this process.
    static func ensureInitialized() throws {
        try initialization.get()
    }

    /// libvips' effective worker concurrency.
    static var vipsConcurrency: Int {
        Int(swift_vips_concurrency_get())
    }

    // MARK: - Capabilities

    private static let discoveredCapabilities: Result<RuntimeCapabilities, HokusaiError> = {
        do {
            try ensureInitialized()
        } catch let error as HokusaiError {
            return .failure(error)
        } catch {
            return .failure(.runtime(FailureContext(operation: "initialize libvips", reason: error.localizedDescription)))
        }
        return .success(discoverCapabilities())
    }()

    /// Discovers native capabilities once and caches the immutable result.
    static func capabilities() throws -> RuntimeCapabilities {
        try discoveredCapabilities.get()
    }

    private static func discoverCapabilities() -> RuntimeCapabilities {
        func exists(_ operation: String) -> Bool { swift_vips_operation_exists(operation) != 0 }

        let loaders: [(ImageFormat, String)] = [
            (.jpeg, "jpegload"), (.png, "pngload"), (.webp, "webpload"), (.gif, "gifload"),
            (.tiff, "tiffload"), (.heif, "heifload"), (.pdf, "pdfload"), (.svg, "svgload"),
        ]
        var inputs = Set(loaders.filter { exists($0.1) }.map(\.0))

        var outputs = Set<ImageFormat>()
        if exists("jpegsave") { outputs.insert(.jpeg) }
        if exists("pngsave") { outputs.insert(.png) }
        if exists("webpsave") { outputs.insert(.webp) }
        if swift_vips_cairo_pdf_available() != 0 { outputs.insert(.pdf) }

        // A HEIF saver may lack an AV1 encoder, and a HEIF loader may lack an
        // AV1 decoder, so AVIF is verified by a round trip of a tiny image.
        if exists("heifsave"), swift_vips_avif_roundtrip_probe() == 0 {
            outputs.insert(.avif)
            inputs.insert(.avif)
        }
        // A failed probe leaves libvips diagnostics behind; do not leak them
        // into the next unrelated error.
        _ = VipsDiagnostics.drain()

        return RuntimeCapabilities(
            libvipsVersion: VipsBackend.version,
            inputFormats: inputs,
            outputFormats: outputs,
            textRendering: exists("text")
        )
    }
}

/// The configure-once, freeze-on-first-use rule, kept free of global state so
/// it can be tested without a fresh process.
struct ConfigurationState {
    private var requested: RuntimeConfiguration?
    private var frozen: RuntimeConfiguration?

    var isFrozen: Bool { frozen != nil }

    /// The frozen configuration, else the requested one, else defaults.
    var effective: RuntimeConfiguration { frozen ?? requested ?? RuntimeConfiguration() }

    mutating func configure(_ configuration: RuntimeConfiguration) throws {
        guard frozen == nil else {
            throw HokusaiError.runtime(.init(
                operation: "configure",
                reason: "runtime configuration is frozen; call configure(_:) before the first Hokusai evaluation, initialize(), or capabilities()"))
        }
        guard requested == nil else {
            throw HokusaiError.runtime(.init(
                operation: "configure",
                reason: "configure(_:) may be called only once per process"))
        }
        requested = configuration
    }

    mutating func freeze() -> RuntimeConfiguration {
        let configuration = effective
        frozen = configuration
        return configuration
    }
}
