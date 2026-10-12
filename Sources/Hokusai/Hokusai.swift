import Foundation
import CVips

/// An immutable image-processing pipeline backed by libvips.
///
/// Create a value from encoded bytes or a local file, append transformations,
/// select an encoder, then evaluate it with ``data()`` or ``write(to:)``.
/// Assigning the value is a safe way to branch work because transformations
/// always return a new pipeline.
///
/// ```swift
/// let card = try Hokusai(url: photoURL)
///     .autoOrient()
///     .resize(width: 1200, height: 630, fit: .cover)
///
/// async let webp = card.webp(quality: 82).data()
/// async let png = card.png().data()
/// ```
///
/// Building a pipeline only records intent and validates options; it performs
/// no native work. The source is opened, transformed, and encoded when a
/// terminal method runs, on Hokusai's evaluation scheduler rather than Swift's
/// cooperative executor. Cancelling the calling task cancels a queued
/// evaluation or asks libvips to stop a running one; both throw
/// `CancellationError`. Decode failures and pixel-dependent errors (such as
/// extending to a smaller canvas) therefore surface from the terminal.
public struct Hokusai: Sendable {
    let plan: ImagePlan
    let terminal: TerminalConfig

    private init(plan: ImagePlan, terminal: TerminalConfig = TerminalConfig()) {
        self.plan = plan
        self.terminal = terminal
    }

    // MARK: - Pipeline input

    /// Creates a pipeline from encoded image bytes.
    ///
    /// The bytes are retained (copy-on-write) until evaluation, so the caller
    /// may reuse or release its own `data` value. The content is not decoded
    /// here; invalid image bytes are reported by the terminal method.
    ///
    /// ```swift
    /// let avatar = try Hokusai(data: upload)
    /// ```
    public init(data: Data, options: InputOptions = .init()) throws {
        try Self.validate(options: options)
        guard !data.isEmpty else {
            throw HokusaiError.invalidInput("encoded data is empty or invalid")
        }
        self.init(plan: .source(.data(data)))
    }

    /// Creates a pipeline from a local file URL.
    ///
    /// Remote URLs are intentionally rejected: networking, timeouts, and
    /// request-size policy belong to the calling server. Read remote content
    /// into `Data` first when that is the desired application behavior. The
    /// file is opened when a terminal method runs.
    public init(url: URL, options: InputOptions = .init()) throws {
        guard url.isFileURL else {
            throw HokusaiError.invalidInput("only file URLs are supported; use init(data:) for in-memory input")
        }
        try Self.validate(options: options)
        self.init(plan: .source(.file(url)))
    }

    /// Creates a pipeline from a path string.
    ///
    /// This compatibility initializer is deprecated because `URL` makes the
    /// local-file requirement explicit.
    @available(*, deprecated, message: "Use init(url:) with a file URL.")
    public init(path: String, options: InputOptions = .init()) throws {
        try self.init(url: URL(fileURLWithPath: path), options: options)
    }

    /// Converts conventional 8-bit RGBA components into Hokusai's unit-range
    /// ``Color`` value.
    ///
    /// Use this at boundaries that receive CSS- or UI-style colour values:
    /// `Hokusai.rgba(red: 255, green: 255, blue: 255)`.
    public static func rgba(red: Double, green: Double, blue: Double, opacity: Double = 255) -> Color {
        Color(red: red / 255, green: green / 255, blue: blue / 255, opacity: opacity / 255)
    }

    // MARK: - Pipeline transformations

    /// Applies the source EXIF orientation before later transformations.
    public func autoOrient() throws -> Self {
        appending(.autoOrient)
    }

    /// Resizes the pipeline using familiar fit and position semantics.
    ///
    /// Supplying one dimension preserves aspect ratio. With both dimensions,
    /// `fit` controls whether Hokusai crops, pads, stretches, or constrains
    /// the result. `position` affects cover crops and `background` affects
    /// contain padding.
    ///
    /// ```swift
    /// let thumbnail = try image.resize(
    ///     width: 400, height: 400, fit: .cover, position: .attention
    /// )
    /// ```
    public func resize(
        width: Int? = nil,
        height: Int? = nil,
        fit: ResizeFit = .cover,
        position: ResizePosition = .center,
        kernel: ResizeKernel = .lanczos3,
        withoutEnlargement: Bool = false,
        withoutReduction: Bool = false,
        background: Color = .transparent
    ) throws -> Self {
        guard width != nil || height != nil else {
            throw HokusaiError.invalidOption(name: "resize", reason: "specify width, height, or both")
        }
        try Self.validate(dimension: width, name: "width")
        try Self.validate(dimension: height, name: "height")
        _ = try background.rgba8()
        return appending(.resize(ResizeStep(
            width: width,
            height: height,
            fit: fit,
            position: position,
            kernel: kernel,
            withoutEnlargement: withoutEnlargement,
            withoutReduction: withoutReduction,
            background: background
        )))
    }

    /// Rotates the pipeline clockwise by a finite number of degrees.
    ///
    /// Use ``autoOrient()`` for camera orientation. This method is for an
    /// intentional visual rotation and fills exposed corners with `background`.
    public func rotate(by degrees: Double, background: Color = .transparent) throws -> Self {
        guard degrees.isFinite else {
            throw HokusaiError.invalidOption(name: "degrees", reason: "must be finite")
        }
        _ = try background.rgba8()
        return appending(.rotate(degrees: degrees, background: background))
    }

    /// Mirrors the image vertically using familiar image-processing terminology.
    public func flip() throws -> Self { appending(.flip) }

    /// Mirrors the image horizontally using familiar image-processing terminology.
    public func flop() throws -> Self { appending(.flop) }

    /// Extracts a rectangle from the current image.
    ///
    /// Coordinates are measured from the current top-left corner, so calling
    /// this before or after ``resize(width:height:fit:position:kernel:withoutEnlargement:withoutReduction:background:)`` produces different results.
    public func extract(x: Int, y: Int, width: Int, height: Int) throws -> Self {
        try Self.validate(dimension: width, name: "width")
        try Self.validate(dimension: height, name: "height")
        return appending(.extract(x: x, y: y, width: width, height: height))
    }

    /// Extends the canvas to an exact size using an anchored background.
    ///
    /// This operation can only add canvas. Use `resize` or `extract` when a
    /// requested size is smaller than the current image; that is detected
    /// when the pipeline is evaluated.
    public func extend(to size: ImageSize, anchor: CanvasAnchor = .center, background: Color = .transparent) throws -> Self {
        try Self.validate(dimension: size.width, name: "width")
        try Self.validate(dimension: size.height, name: "height")
        _ = try background.rgba8()
        return appending(.extend(to: size, anchor: anchor, background: background))
    }

    /// Removes edges whose pixels are similar to the image background.
    ///
    /// `threshold` controls tolerance: lower values remove only nearly
    /// identical borders, while higher values remove a broader range.
    public func trim(threshold: Double = 10) throws -> Self {
        guard threshold.isFinite, threshold >= 0 else {
            throw HokusaiError.invalidOption(name: "threshold", reason: "must be a finite value greater than or equal to zero")
        }
        return appending(.trim(threshold: threshold))
    }

    /// Applies a Gaussian blur with a positive pixel sigma.
    ///
    /// Larger sigma values blur a wider area and require more work.
    public func blur(sigma: Double = 1) throws -> Self {
        guard sigma.isFinite, sigma > 0 else {
            throw HokusaiError.invalidOption(name: "sigma", reason: "must be a finite value greater than zero")
        }
        return appending(.blur(sigma: sigma))
    }

    /// Sharpens the pipeline using libvips' unsharp-mask operation.
    public func sharpen(sigma: Double = 1) throws -> Self {
        guard sigma.isFinite, sigma > 0 else {
            throw HokusaiError.invalidOption(name: "sigma", reason: "must be a finite value greater than zero")
        }
        return appending(.sharpen(sigma: sigma))
    }

    /// Converts the pipeline to a single-channel grayscale image.
    public func grayscale() throws -> Self {
        appending(.grayscale)
    }

    /// Maps source luminance into the supplied sRGB colour.
    public func tint(_ color: Color) throws -> Self {
        _ = try color.rgba8()
        return appending(.tint(color))
    }

    /// Normalizes contrast using libvips histogram normalization.
    public func normalize() throws -> Self {
        appending(.normalize)
    }

    /// Converts the pipeline to a supported output colour space.
    public func convert(to colorSpace: ColorSpace) throws -> Self {
        switch colorSpace {
        case .sRGB: appending(.convertToSRGB)
        case .grayscale: appending(.grayscale)
        }
    }

    /// Adds an opaque alpha band when the pipeline does not already have one.
    public func ensureAlpha() throws -> Self {
        appending(.ensureAlpha)
    }

    /// Flattens alpha onto a solid background colour.
    public func flatten(background: Color = .white) throws -> Self {
        _ = try background.rgba8()
        return appending(.flatten(background: background))
    }

    /// Removes alpha by compositing the image over the supplied background.
    public func removeAlpha(background: Color = .white) throws -> Self {
        try flatten(background: background)
    }

    /// Composites layers over the pipeline in array order.
    ///
    /// Later layers draw over earlier layers. Each layer may reuse another
    /// pipeline, allowing a logo or watermark to be prepared once and applied
    /// to many base images. Only a layer's image transformations apply; its
    /// encoder and metadata settings are ignored.
    public func composite(_ layers: [CompositeLayer]) throws -> Self {
        let steps = try layers.map { layer in
            guard layer.opacity.isFinite, (0...1).contains(layer.opacity) else {
                throw HokusaiError.invalidOption(name: "opacity", reason: "must be a finite value from 0 through 1")
            }
            return LayerStep(plan: layer.source.plan, x: layer.x, y: layer.y, blend: layer.blend, opacity: layer.opacity)
        }
        return appending(.composite(steps))
    }

    /// Draws text onto the pipeline using the existing libvips/Pango renderer.
    ///
    /// Text styling remains intentionally typed by `TextOptions` until the
    /// dedicated typography redesign lands; the pipeline and output semantics
    /// are already the same as every other 1.0 transformation.
    public func drawText(_ text: String, x: Int, y: Int, options: TextOptions = .init()) throws -> Self {
        appending(.drawText(text, x: x, y: y, options: options))
    }

    // MARK: - Output configuration

    /// Selects an output encoder for subsequent terminal operations.
    ///
    /// Selecting a second encoder replaces the first; no bytes are produced
    /// until ``data()`` or ``write(to:)`` is called.
    public func encode(as format: OutputFormat) throws -> Self {
        try Self.validate(output: format)
        var terminal = terminal
        terminal.encoder = format
        return Self(plan: plan, terminal: terminal)
    }

    /// Selects JPEG output with optional progressive encoding.
    public func jpeg(quality: Int = 80, progressive: Bool = false) throws -> Self {
        try encode(as: .jpeg(.init(quality: quality, progressive: progressive)))
    }

    /// Selects PNG output with a compression level from 0 through 9.
    public func png(compressionLevel: Int = 6, progressive: Bool = false) throws -> Self {
        try encode(as: .png(.init(compressionLevel: compressionLevel, progressive: progressive)))
    }

    /// Selects WebP output.
    ///
    /// `effort` trades CPU time for compression efficiency; `lossless` changes
    /// the encoder mode rather than merely increasing quality.
    public func webp(quality: Int = 80, effort: Int = 4, lossless: Bool = false) throws -> Self {
        try encode(as: .webp(.init(quality: quality, effort: effort, lossless: lossless)))
    }

    /// Selects AVIF output.
    public func avif(quality: Int = 50, effort: Int = 4, lossless: Bool = false) throws -> Self {
        try encode(as: .avif(.init(quality: quality, effort: effort, lossless: lossless)))
    }

    /// Configures a one-page Cairo PDF document from the current image pipeline.
    ///
    /// The resulting PDF contains rasterized pipeline output. It is suitable
    /// for image reports but does not preserve selectable vector text.
    public func pdf(pageSize: PDFPageSize = .image, dpi: Double = 72) throws -> Self {
        try encode(as: .pdf(.init(pageSize: pageSize, dpi: dpi)))
    }

    /// Preserves source metadata when the selected encoder supports it.
    public func preserveMetadata() throws -> Self {
        var terminal = terminal
        terminal.preservesMetadata = true
        return Self(plan: plan, terminal: terminal)
    }

    /// Removes non-essential source metadata from encoder output (the default).
    public func removeMetadata() throws -> Self {
        var terminal = terminal
        terminal.preservesMetadata = false
        return Self(plan: plan, terminal: terminal)
    }

    /// Returns current pipeline metadata.
    ///
    /// This builds the native graph on the calling thread and may read source
    /// headers, but does not promise to evaluate every output pixel.
    public func metadata() throws -> ImageMetadata {
        do {
            return try Evaluator.lower(plan, context: EvaluationContext()).metadata()
        } catch {
            throw HokusaiError.pipeline(error, operation: "read metadata", category: .transform)
        }
    }

    /// Evaluates and encodes the pipeline on Hokusai's evaluation scheduler.
    ///
    /// Call an encoder method first. The returned ``Output`` includes both the
    /// owned bytes and the actual encoded dimensions, format, and byte count.
    public func data() async throws -> Output {
        guard let format = terminal.encoder else {
            throw HokusaiError.invalidOption(name: "output format", reason: "call jpeg(), png(), webp(), avif(), pdf(), or encode(as:) before data()")
        }
        let plan = plan, terminal = terminal
        return try await EvaluationScheduler.shared.run { context in
            try Evaluator.encode(plan, terminal, as: format, context: context)
        }
    }

    /// Evaluates and writes the pipeline to a local file URL.
    ///
    /// If no encoder was selected, the file extension determines the format.
    /// Parent directories are not created automatically.
    @discardableResult
    public func write(to url: URL) async throws -> OutputInfo {
        guard url.isFileURL else {
            throw HokusaiError.invalidInput("write(to:) accepts only file URLs")
        }
        let format = try terminal.encoder ?? Self.outputFormat(from: url)
        let plan = plan, terminal = terminal
        return try await EvaluationScheduler.shared.run { context in
            try Evaluator.write(plan, terminal, as: format, to: url, context: context)
        }
    }

    // MARK: - Pipeline helpers

    private func appending(_ operation: ImageOperation) -> Self {
        Self(plan: plan.appending(operation), terminal: terminal)
    }

    private static func validate(options: InputOptions) throws {
        if options.page != nil || options.pages != nil || options.failOn != .warning {
            throw HokusaiError.unsupported(feature: "non-default InputOptions are not implemented yet")
        }
    }

    private static func validate(dimension: Int?, name: String) throws {
        guard let dimension else { return }
        guard dimension > 0, Int32(exactly: dimension) != nil else {
            throw HokusaiError.invalidOption(name: name, reason: "must be in 1...\(Int32.max)")
        }
    }

    private static func validate(output: OutputFormat) throws {
        func quality(_ value: Int) throws { guard (1...100).contains(value) else { throw HokusaiError.invalidOption(name: "quality", reason: "must be in 1...100") } }
        func effort(_ value: Int) throws { guard (0...9).contains(value) else { throw HokusaiError.invalidOption(name: "effort", reason: "must be in 0...9") } }
        switch output {
        case .jpeg(let options): try quality(options.quality)
        case .png(let options): guard (0...9).contains(options.compressionLevel) else { throw HokusaiError.invalidOption(name: "compressionLevel", reason: "must be in 0...9") }
        case .webp(let options): try quality(options.quality); try effort(options.effort)
        case .avif(let options): try quality(options.quality); try effort(options.effort)
        case .pdf(let options):
            guard options.dpi.isFinite, options.dpi > 0 else {
                throw HokusaiError.invalidOption(name: "dpi", reason: "must be a finite value greater than zero")
            }
        }
    }

    private static func outputFormat(from url: URL) throws -> OutputFormat {
        guard let format = ImageFormat.from(fileExtension: url.pathExtension) else {
            throw HokusaiError.invalidOption(name: "output URL", reason: "use a supported image extension or select an encoder")
        }
        switch format {
        case .jpeg: return .jpeg()
        case .png: return .png()
        case .webp: return .webp()
        case .avif: return .avif()
        case .pdf: return .pdf()
        default: throw HokusaiError.unsupported(feature: "writing \(format.rawValue)")
        }
    }

    // MARK: - Lifecycle Management

    /// Initialize the libvips runtime.
    ///
    /// libvips is process-scoped: it is initialized at most once and remains
    /// available until the process exits. Repeated and concurrent calls are
    /// safe. Every native entry point initializes the runtime automatically,
    /// so an explicit call is only needed to surface initialization failures
    /// at application startup.
    ///
    /// - Throws: ``HokusaiError/initializationFailed(_:)`` if libvips could
    ///   not be initialized. The failure is final for the process.
    public static func initialize() throws {
        try VipsRuntime.ensureInitialized()
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

    /// The version string reported by the linked libvips runtime.
    public static var vipsVersion: String {
        return VipsBackend.version
    }

    /// Deprecated compatibility placeholder for the removed ImageMagick backend.
    @available(*, deprecated, message: "ImageMagick backend was removed. Use vipsVersion instead.")
    public static var magickVersion: String {
        return "removed (native runtime)"
    }

    /// A human-readable Hokusai and libvips version summary.
    public static var version: String {
        return "Hokusai (libvips \(vipsVersion))"
    }

    /// Gets or sets libvips' process-wide worker-thread concurrency.
    ///
    /// Setting `0` restores libvips' default. Changes affect every image in
    /// the process, so configure this during application startup rather than
    /// per request.
    public static var vipsConcurrency: Int {
        get { VipsBackend.concurrency }
        set { VipsBackend.concurrency = newValue }
    }
}
