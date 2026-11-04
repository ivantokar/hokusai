import Foundation
import CVips
import CCairo

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
        if configuration.blockUntrustedOperations { swift_vips_block_untrusted(1) }
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
        let (usable, blocked) = classifyLoaders(loaders, exists: exists, isBlocked: { swift_vips_operation_blocked($0) != 0 })
        var inputs = usable

        var outputs = Set<ImageFormat>()
        if exists("jpegsave") { outputs.insert(.jpeg) }
        if exists("pngsave") { outputs.insert(.png) }
        if exists("webpsave") { outputs.insert(.webp) }
        if exists("tiffsave") { outputs.insert(.tiff) }
        if exists("gifsave") { outputs.insert(.gif) }
        if hokusai_cairo_pdf_available() != 0 { outputs.insert(.pdf) }

        // The HEIF saver and loader are optional plugins, and each direction has
        // its own codecs: an AV1 decoder can exist without an AV1 encoder and the
        // other way round. Each is therefore probed alone: an encoder by encoding
        // a tiny image, a decoder by decoding a small embedded AVIF.
        let heif = heifCapabilities(
            saverExists: exists("heifsave"), loaderUsable: usable.contains(.heif),
            encodesAV1: exists("heifsave") && swift_vips_heif_encode_probe(1) == 0,
            encodesHEVC: exists("heifsave") && swift_vips_heif_encode_probe(0) == 0,
            decodesAV1: usable.contains(.heif) && swift_vips_avif_decode_probe() == 0)
        inputs.formUnion(heif.inputs)
        outputs.formUnion(heif.outputs)
        // A failed probe leaves libvips diagnostics behind; do not leak them
        // into the next unrelated error.
        _ = VipsDiagnostics.drain()

        return RuntimeCapabilities(
            libvipsVersion: vips_version_string().map { String(cString: $0) } ?? "unknown",
            cairoVersion: cairo_version_string().map { String(cString: $0) } ?? "unknown",
            inputFormats: inputs,
            outputFormats: outputs,
            blockedInputFormats: blocked,
            textRendering: exists("text"),
            heifCompressions: heif.compressions,
            pngPalette: exists("pngsave") && swift_vips_png_palette_probe() == 0
        )
    }
}

/// What HEIF and AVIF support follows from the probes, one per direction and codec.
///
/// Reading and writing are independent: a runtime with only an AV1 decoder
/// reads AVIF and cannot write it, and one with only an encoder is the reverse.
/// `.heif` input comes from the loader itself and is not decided here.
func heifCapabilities(
    saverExists: Bool, loaderUsable: Bool, encodesAV1: Bool, encodesHEVC: Bool, decodesAV1: Bool
) -> (inputs: Set<ImageFormat>, outputs: Set<ImageFormat>, compressions: Set<HEIFCompression>) {
    var compressions = Set<HEIFCompression>()
    if saverExists, encodesAV1 { compressions.insert(.av1) }
    if saverExists, encodesHEVC { compressions.insert(.hevc) }
    var inputs = Set<ImageFormat>(), outputs = Set<ImageFormat>()
    if loaderUsable, decodesAV1 { inputs.insert(.avif) }
    if compressions.contains(.av1) { outputs.insert(.avif) }
    if !compressions.isEmpty { outputs.insert(.heif) }
    return (inputs, outputs, compressions)
}

/// Splits the loaders libvips has into those that can run and those it blocks.
func classifyLoaders(
    _ loaders: [(ImageFormat, String)], exists: (String) -> Bool, isBlocked: (String) -> Bool
) -> (usable: Set<ImageFormat>, blocked: Set<ImageFormat>) {
    var usable = Set<ImageFormat>(), blocked = Set<ImageFormat>()
    for (format, operation) in loaders where exists(operation) {
        if isBlocked(operation) { blocked.insert(format) } else { usable.insert(format) }
    }
    return (usable, blocked)
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
