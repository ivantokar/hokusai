import Foundation
import CVips

/// PURPOSE: Main static API entry point for Hokusai image processing.
/// CONSTRAINTS:
/// - Initialize libvips exactly once during process startup.
/// - Do not instantiate this type directly.
/// AI HINTS:
/// - Keep this surface minimal and stable.
/// - Route all image loading through libvips-backed helpers.
public struct Hokusai: Sendable {
    /// The immutable native pipeline backing this value.
    ///
    /// `HokusaiImage` is an internal legacy adapter handle. It is immutable
    /// after construction and its ownership policy is covered by the pipeline
    /// concurrency tests; callers never receive it from the 1.0 surface.
    private let pipeline: HokusaiImage?
    private let selectedOutput: OutputFormat?
    private let preservesMetadata: Bool

    private init() {
        self.pipeline = nil
        self.selectedOutput = nil
        self.preservesMetadata = false
    }

    private init(pipeline: HokusaiImage, selectedOutput: OutputFormat? = nil, preservesMetadata: Bool = false) {
        self.pipeline = pipeline
        self.selectedOutput = selectedOutput
        self.preservesMetadata = preservesMetadata
    }

    // MARK: - Pipeline input

    /// Creates an immutable pipeline from encoded image data.
    ///
    /// Construction may read source headers synchronously. Pixel evaluation and
    /// encoding occur only in terminal methods such as ``data()``.
    public init(data: Data, options: InputOptions = .init()) throws {
        try Self.validate(options: options)
        do {
            self.init(pipeline: try Self.image(from: data))
        } catch {
            throw Self.pipelineError(error, operation: "decode input data", category: .decode)
        }
    }

    /// Creates an immutable pipeline from a local file URL.
    public init(url: URL, options: InputOptions = .init()) throws {
        guard url.isFileURL else {
            throw HokusaiError.invalidInput("only file URLs are supported; use init(data:) for in-memory input")
        }
        try Self.validate(options: options)
        do {
            self.init(pipeline: try Self.image(from: url.path))
        } catch {
            throw Self.pipelineError(error, operation: "decode \(url.lastPathComponent)", category: .decode)
        }
    }

    /// Creates a pipeline from a path string.
    @available(*, deprecated, message: "Use init(url:) with a file URL.")
    public init(path: String, options: InputOptions = .init()) throws {
        try self.init(url: URL(fileURLWithPath: path), options: options)
    }

    /// Creates a portable colour from conventional 8-bit RGBA components.
    public static func rgba(red: Double, green: Double, blue: Double, opacity: Double = 255) -> Color {
        Color(red: red / 255, green: green / 255, blue: blue / 255, opacity: opacity / 255)
    }

    // MARK: - Pipeline transformations

    /// Applies EXIF orientation to the pipeline.
    public func autoOrient() throws -> Self {
        try transforming("auto orient") { try $0.autoRotate() }
    }

    /// Resizes the pipeline using familiar fit and position semantics.
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

        var options = ResizeOptions()
        options.fit = fit
        options.position = position.legacyPosition
        options.kernel = kernel.legacyKernel
        options.withoutEnlargement = withoutEnlargement
        options.withoutReduction = withoutReduction
        options.background = try background.rgba8()
        return try transforming("resize") { try $0.resize(width: width, height: height, options: options) }
    }

    /// Rotates the pipeline clockwise by the supplied number of degrees.
    public func rotate(by degrees: Double, background: Color = .transparent) throws -> Self {
        guard degrees.isFinite else {
            throw HokusaiError.invalidOption(name: "degrees", reason: "must be finite")
        }
        return try transforming("rotate") { try $0.rotate(angle: .custom(degrees), background: try background.rgba8()) }
    }

    /// Mirrors the image vertically using familiar image-processing terminology.
    public func flip() throws -> Self { try transforming("flip") { try $0.flipVertical() } }

    /// Mirrors the image horizontally using familiar image-processing terminology.
    public func flop() throws -> Self { try transforming("flop") { try $0.flipHorizontal() } }

    /// Extracts a rectangle from the image.
    public func extract(x: Int, y: Int, width: Int, height: Int) throws -> Self {
        try Self.validate(dimension: width, name: "width")
        try Self.validate(dimension: height, name: "height")
        return try transforming("extract") { try $0.crop(left: x, top: y, width: width, height: height) }
    }

    /// Extends the canvas to an exact size using an anchored background.
    public func extend(to size: ImageSize, anchor: CanvasAnchor = .center, background: Color = .transparent) throws -> Self {
        try Self.validate(dimension: size.width, name: "width")
        try Self.validate(dimension: size.height, name: "height")
        let legacy = try image()
        let imageWidth = try legacy.width
        let imageHeight = try legacy.height
        guard size.width >= imageWidth, size.height >= imageHeight else {
            throw HokusaiError.invalidOption(name: "size", reason: "extend cannot reduce an image; use resize or extract")
        }
        let offset = anchor.offset(imageWidth: imageWidth, imageHeight: imageHeight, canvasWidth: size.width, canvasHeight: size.height)
        let rgba = try background.rgba8()
        let area = rgba.withUnsafeBufferPointer { swift_vips_array_double_new($0.baseAddress, Int32($0.count)) }
        guard let area else {
            throw HokusaiError.runtime(.init(operation: "extend", message: "could not allocate native background colour"))
        }
        defer { vips_area_unref(UnsafeMutablePointer(mutating: UnsafeRawPointer(area).assumingMemoryBound(to: VipsArea.self))) }
        var output: UnsafeMutablePointer<CVips.VipsImage>?
        let pointer = try legacy.ensureVipsBackend().getPointer()
        guard swift_vips_embed(pointer, &output, Int32(offset.x), Int32(offset.y), Int32(size.width), Int32(size.height), area) == 0, let output else {
            VipsBackend.discardPartialImage(output)
            throw HokusaiError.transform(.init(operation: "extend", message: VipsBackend.getLastError()))
        }
        return Self(pipeline: HokusaiImage(backend: .vips(VipsBackend(takingOwnership: output))), selectedOutput: selectedOutput, preservesMetadata: preservesMetadata)
    }

    /// Removes edges similar to the image background.
    public func trim(threshold: Double = 10) throws -> Self {
        guard threshold.isFinite, threshold >= 0 else {
            throw HokusaiError.invalidOption(name: "threshold", reason: "must be a finite value greater than or equal to zero")
        }
        let legacy = try image()
        let pointer = try legacy.ensureVipsBackend().getPointer()
        var left: Int32 = 0, top: Int32 = 0, width: Int32 = 0, height: Int32 = 0
        guard swift_vips_find_trim(pointer, &left, &top, &width, &height, threshold) == 0 else {
            throw HokusaiError.transform(.init(operation: "trim", message: VipsBackend.getLastError()))
        }
        return try extract(x: Int(left), y: Int(top), width: Int(width), height: Int(height))
    }

    /// Applies a Gaussian blur with a positive pixel sigma.
    public func blur(sigma: Double = 1) throws -> Self {
        guard sigma.isFinite, sigma > 0 else {
            throw HokusaiError.invalidOption(name: "sigma", reason: "must be a finite value greater than zero")
        }
        return try nativeTransform("blur") { input, output in
            swift_vips_gaussblur(input, output, sigma)
        }
    }

    /// Sharpens the pipeline using libvips' unsharp-mask operation.
    public func sharpen(sigma: Double = 1) throws -> Self {
        guard sigma.isFinite, sigma > 0 else {
            throw HokusaiError.invalidOption(name: "sigma", reason: "must be a finite value greater than zero")
        }
        return try nativeTransform("sharpen") { input, output in
            swift_vips_sharpen(input, output, sigma)
        }
    }

    /// Converts the pipeline to a single-channel grayscale image.
    public func grayscale() throws -> Self {
        try nativeTransform("grayscale") { input, output in
            swift_vips_colourspace_bw(input, output)
        }
    }

    /// Maps source luminance into the supplied sRGB colour.
    public func tint(_ color: Color) throws -> Self {
        let rgba = try color.rgba8()
        return try nativeTransform("tint") { input, output in
            swift_vips_tint(input, output, rgba[0], rgba[1], rgba[2])
        }
    }

    /// Normalizes image contrast using libvips histogram normalization.
    public func normalize() throws -> Self {
        try nativeTransform("normalize") { input, output in
            swift_vips_hist_norm(input, output)
        }
    }

    /// Converts the pipeline to a supported output colour space.
    public func convert(to colorSpace: ColorSpace) throws -> Self {
        switch colorSpace {
        case .sRGB:
            return try nativeTransform("convert to sRGB") { input, output in
                swift_vips_colourspace_srgb(input, output)
            }
        case .grayscale:
            return try grayscale()
        }
    }

    /// Adds an opaque alpha band when the pipeline does not already have one.
    public func ensureAlpha() throws -> Self {
        let legacy = try image()
        if try legacy.hasAlpha { return self }
        return try nativeTransform("ensure alpha") { input, output in
            swift_vips_addalpha(input, output)
        }
    }

    /// Flattens alpha onto a solid background colour.
    public func flatten(background: Color = .white) throws -> Self {
        let rgba = try background.rgba8()
        let legacy = try image()
        let pointer = try legacy.ensureVipsBackend().getPointer()
        let area = rgba.withUnsafeBufferPointer { swift_vips_array_double_new($0.baseAddress, Int32($0.count)) }
        guard let area else {
            throw HokusaiError.runtime(.init(operation: "flatten", message: "could not allocate native background colour"))
        }
        defer { vips_area_unref(UnsafeMutablePointer(mutating: UnsafeRawPointer(area).assumingMemoryBound(to: VipsArea.self))) }
        var output: UnsafeMutablePointer<CVips.VipsImage>?
        guard swift_vips_flatten(pointer, &output, area) == 0, let output else {
            VipsBackend.discardPartialImage(output)
            throw HokusaiError.transform(.init(operation: "flatten", message: VipsBackend.getLastError()))
        }
        return Self(pipeline: HokusaiImage(backend: .vips(VipsBackend(takingOwnership: output))), selectedOutput: selectedOutput, preservesMetadata: preservesMetadata)
    }

    /// Removes alpha by compositing the image over the supplied background.
    public func removeAlpha(background: Color = .white) throws -> Self {
        try flatten(background: background)
    }

    /// Composites layers over the pipeline in array order.
    public func composite(_ layers: [CompositeLayer]) throws -> Self {
        var result = try image()
        for layer in layers {
            guard layer.opacity.isFinite, (0...1).contains(layer.opacity) else {
                throw HokusaiError.invalidOption(name: "opacity", reason: "must be a finite value from 0 through 1")
            }
            do {
                result = try result.composite(
                    overlay: try layer.source.image(),
                    x: layer.x,
                    y: layer.y,
                    options: CompositeOptions(mode: layer.blend, opacity: layer.opacity)
                )
            } catch {
                throw Self.pipelineError(error, operation: "composite layer", category: .transform)
            }
        }
        return Self(pipeline: result, selectedOutput: selectedOutput, preservesMetadata: preservesMetadata)
    }

    /// Draws text onto the pipeline using the existing libvips/Pango renderer.
    ///
    /// Text styling remains intentionally typed by `TextOptions` until the
    /// dedicated typography redesign lands; the pipeline and output semantics
    /// are already the same as every other 1.0 transformation.
    public func drawText(_ text: String, x: Int, y: Int, options: TextOptions = .init()) throws -> Self {
        try transforming("draw text") { try $0.drawText(text, x: x, y: y, options: options) }
    }

    // MARK: - Output configuration

    /// Selects an output encoder for subsequent terminal operations.
    public func encode(as format: OutputFormat) throws -> Self {
        try Self.validate(output: format)
        return Self(pipeline: try image(), selectedOutput: format, preservesMetadata: preservesMetadata)
    }

    public func jpeg(quality: Int = 80, progressive: Bool = false) throws -> Self {
        try encode(as: .jpeg(.init(quality: quality, progressive: progressive)))
    }

    public func png(compressionLevel: Int = 6, progressive: Bool = false) throws -> Self {
        try encode(as: .png(.init(compressionLevel: compressionLevel, progressive: progressive)))
    }

    public func webp(quality: Int = 80, effort: Int = 4, lossless: Bool = false) throws -> Self {
        try encode(as: .webp(.init(quality: quality, effort: effort, lossless: lossless)))
    }

    public func avif(quality: Int = 50, effort: Int = 4, lossless: Bool = false) throws -> Self {
        try encode(as: .avif(.init(quality: quality, effort: effort, lossless: lossless)))
    }

    /// Configures a one-page Cairo PDF document from the current image pipeline.
    public func pdf(pageSize: PDFPageSize = .image, dpi: Double = 72) throws -> Self {
        try encode(as: .pdf(.init(pageSize: pageSize, dpi: dpi)))
    }

    /// Preserves source metadata when the selected encoder supports it.
    public func preserveMetadata() throws -> Self {
        Self(pipeline: try image(), selectedOutput: selectedOutput, preservesMetadata: true)
    }

    /// Removes non-essential source metadata from encoder output (the default).
    public func removeMetadata() throws -> Self {
        Self(pipeline: try image(), selectedOutput: selectedOutput, preservesMetadata: false)
    }

    /// Returns current pipeline metadata. This may load source headers but does
    /// not promise to evaluate every output pixel.
    public func metadata() throws -> ImageMetadata {
        do {
            return try image().metadata()
        } catch {
            throw Self.pipelineError(error, operation: "read metadata", category: .transform)
        }
    }

    /// Evaluates and encodes the pipeline on Hokusai's bounded executor.
    public func data() async throws -> Output {
        let image = try self.image()
        guard let format = selectedOutput else {
            throw HokusaiError.invalidOption(name: "output format", reason: "call jpeg(), png(), webp(), avif(), pdf(), or encode(as:) before data()")
        }
        return try await PipelineExecutor.run {
            do {
                var options = format.legacySaveOptions
                options.stripMetadata = !preservesMetadata
                let data: Data
                switch format {
                case .pdf(let pdfOptions): data = try image.toPDF(options: pdfOptions)
                default: data = try image.toBuffer(options: options)
                }
                return Output(data: data, info: OutputInfo(format: format.imageFormat, width: try image.width, height: try image.height, size: data.count))
            } catch {
                throw Self.pipelineError(error, operation: "encode \(format.imageFormat.rawValue)", category: .encode)
            }
        }
    }

    /// Evaluates and writes the pipeline to a local file URL.
    @discardableResult
    public func write(to url: URL) async throws -> OutputInfo {
        guard url.isFileURL else {
            throw HokusaiError.invalidInput("write(to:) accepts only file URLs")
        }
        let image = try self.image()
        let format: OutputFormat
        if let selectedOutput {
            format = selectedOutput
        } else {
            format = try Self.outputFormat(from: url)
        }
        return try await PipelineExecutor.run {
            do {
                var options = format.legacySaveOptions
                options.stripMetadata = !preservesMetadata
                switch format {
                case .pdf(let pdfOptions):
                    try image.toPDF(options: pdfOptions).write(to: url)
                default:
                    try image.toFile(url.path, options: options)
                }
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return OutputInfo(format: format.imageFormat, width: try image.width, height: try image.height, size: size)
            } catch {
                throw Self.pipelineError(error, operation: "write \(format.imageFormat.rawValue)", category: .encode)
            }
        }
    }

    // MARK: - Pipeline helpers

    private enum PipelineFailureCategory { case decode, transform, encode }

    private func image() throws -> HokusaiImage {
        guard let pipeline else {
            throw HokusaiError.runtime(.init(operation: "pipeline", message: "static Hokusai APIs do not represent an image pipeline"))
        }
        return pipeline
    }

    private func transforming(_ operation: String, _ transform: (HokusaiImage) throws -> HokusaiImage) throws -> Self {
        do {
            return Self(pipeline: try transform(try image()), selectedOutput: selectedOutput, preservesMetadata: preservesMetadata)
        } catch {
            throw Self.pipelineError(error, operation: operation, category: .transform)
        }
    }

    private func nativeTransform(
        _ operation: String,
        _ transform: (UnsafeMutablePointer<CVips.VipsImage>, UnsafeMutablePointer<UnsafeMutablePointer<CVips.VipsImage>?>) -> Int32
    ) throws -> Self {
        let legacy = try image()
        let input = try legacy.ensureVipsBackend().getPointer()
        var output: UnsafeMutablePointer<CVips.VipsImage>?
        guard transform(input, &output) == 0, let output else {
            VipsBackend.discardPartialImage(output)
            throw HokusaiError.transform(.init(operation: operation, message: VipsBackend.getLastError()))
        }
        return Self(pipeline: HokusaiImage(backend: .vips(VipsBackend(takingOwnership: output))), selectedOutput: selectedOutput, preservesMetadata: preservesMetadata)
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

    private static func pipelineError(_ error: Error, operation: String, category: PipelineFailureCategory) -> HokusaiError {
        if let error = error as? HokusaiError {
            switch error {
            case .invalidInput, .invalidOption, .unsupported, .decode, .transform, .encode, .io, .cancelled, .runtime:
                return error
            case .fileNotFound(let path): return .io(url: URL(fileURLWithPath: path), operation: .read, reason: "file not found")
            case .invalidImageData: return .invalidInput("encoded data is empty or invalid")
            default: break
            }
        }
        let context = FailureContext(operation: operation, message: error.localizedDescription)
        switch category {
        case .decode: return .decode(context)
        case .transform: return .transform(context)
        case .encode: return .encode(context)
        }
    }

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
    @available(*, deprecated, message: "Ordinary applications should not shut down libvips. The process reclaims it at exit.")
    public static func shutdown() throws {
        try VipsBackend.shutdown()
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
        return "removed (native runtime)"
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
