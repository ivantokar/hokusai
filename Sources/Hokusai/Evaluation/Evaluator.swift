import Foundation
import CVips

/// Lowers immutable plans to libvips graphs and drives terminal sinks.
///
/// Every method performs native work and must run inside one
/// `EvaluationScheduler` slot. Composite layers are lowered within the same
/// call; the evaluator never schedules work or acquires another slot.
/// libvips stays the pixel engine: lowering only builds its lazy graph, and
/// pixels are computed when a sink pulls them.
///
/// Errors are classified where they occur (source, operation, encoder, file
/// sink) and passed through unchanged; composite layers only add their scope
/// to the operation label.
enum Evaluator {
    /// Builds the native image graph described by `plan`.
    ///
    /// Cancellation is checked between steps; a cancelled evaluation throws
    /// `CancellationError` before starting the next native operation.
    static func lower(_ plan: ImagePlan, context: EvaluationContext) throws -> NativeImage {
        try classifyingSourceFailures(in: context) {
            try build(plan, context: context, scope: nil)
        }
    }

    /// Evaluates `plan` and returns encoded bytes.
    static func encode(_ plan: ImagePlan, _ terminal: TerminalConfig, as format: OutputFormat, context: EvaluationContext) throws -> Output {
        let encoder = try selectEncoder(format, terminal)
        return try classifyingSourceFailures(in: context) {
            let image = try context.sink(for: build(plan, context: context, scope: nil))
            context.trace?.record(.sinkSelected("memory \(format.imageFormat.rawValue)"))
            switch encoder {
            case .pdf(let options):
                let sink = PDFOutputSink(destination: .memory, isCancelled: { context.isCancelled })
                let result = try image.writePDF(options, into: sink)
                let data = sink.takeData()
                return Output(data: data, info: OutputInfo(
                    format: .pdf, width: result.rasterWidth, height: result.rasterHeight, byteCount: data.count, pdf: result.details))
            case .raster(let encoder):
                let data = try image.encoded(encoder)
                return Output(data: data, info: OutputInfo(format: format.imageFormat, width: image.width, height: image.height, byteCount: data.count))
            }
        }
    }

    /// Evaluates `plan` and writes it to a local file.
    static func write(_ plan: ImagePlan, _ terminal: TerminalConfig, as format: OutputFormat, to url: URL, context: EvaluationContext) throws -> OutputInfo {
        let encoder = try selectEncoder(format, terminal)
        return try classifyingSourceFailures(in: context) {
            let image = try context.sink(for: build(plan, context: context, scope: nil))
            context.trace?.record(.sinkSelected("file \(format.imageFormat.rawValue)"))
            switch encoder {
            case .pdf(let options):
                let sink = PDFOutputSink(destination: .file(url), isCancelled: { context.isCancelled })
                let result = try image.writePDF(options, into: sink)
                return OutputInfo(
                    format: .pdf, width: result.rasterWidth, height: result.rasterHeight, byteCount: sink.byteCount, pdf: result.details)
            case .raster(let encoder):
                let size = try image.write(encoder, to: url)
                return OutputInfo(format: format.imageFormat, width: image.width, height: image.height, byteCount: size)
            }
        }
    }

    // MARK: - Source inspection

    /// Opens `source` under its options and reads its header.
    ///
    /// This is the whole of metadata inspection: it lowers no operations and
    /// reads no pixels, so it describes only what the source reported.
    static func inspect(_ source: ImageSource, context: EvaluationContext) throws -> ImageMetadata {
        try context.checkCancellation()
        switch source {
        case .file(let url, let options):
            let image = try NativeImage.open(path: url.path, options: options)
            let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            return image.sourceMetadata(sourceByteSize: size)
        case .data(let data, let options):
            let image = try NativeImage.open(data: data, options: options)
            return image.sourceMetadata(sourceByteSize: data.count)
        case .text(let text):
            return try NativeImage.renderText(text).sourceMetadata(sourceByteSize: nil)
        }
    }

    // MARK: - Lowering

    /// Reclassifies a transform or encode failure as a decode failure when a
    /// source reported that it could not produce pixels.
    ///
    /// Decoders surface truncation and corruption only while pixels are read,
    /// deep inside whatever operation pulled them. The source probe records
    /// the failure where it happened, so no native error text is consulted.
    private static func classifyingSourceFailures<T>(in context: EvaluationContext, _ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as HokusaiError {
            switch error {
            case .transform, .encode:
                if let failure = context.sourceFailure() {
                    throw HokusaiError.decode(.native(failure.label, failure.reason))
                }
            default:
                break
            }
            throw error
        }
    }

    /// Lowers one plan; `scope` labels sources of composite layers.
    ///
    /// Operations are lowered one-to-one and in written order. The planner may
    /// mark a step as a proven identity, and a node already built in this
    /// evaluation is reused instead of rebuilt (see ``PlannerRule``).
    private static func build(_ plan: ImagePlan, context: EvaluationContext, scope: String?) throws -> NativeImage {
        let chain = plan.chain
        let steps = Planner.plan(chain.steps.map(\.operation), options: context.planner)
        let label = scope.map { "\($0) / \(chain.source.decodeLabel)" } ?? chain.source.decodeLabel
        // A forward-only stream cannot serve two readers, so sequential
        // sources are never shared.
        let shareable = context.planner.isEnabled(.subplanMemoisation) && chain.source.options.access != .sequential

        try context.checkCancellation()

        // Start from the most advanced node of this chain that is already built.
        var image: NativeImage?
        var next = 0
        if shareable {
            for index in stride(from: chain.steps.count - 1, through: 0, by: -1) {
                if let hit = context.memoised(chain.steps[index].id) {
                    image = hit
                    next = index + 1
                    context.trace?.record(.memoisationHit(chain.steps[index].operation.name))
                    break
                }
            }
            if image == nil, let hit = context.memoised(chain.sourceID) {
                image = hit
                context.trace?.record(.memoisationHit(label))
            }
        }

        var current: NativeImage
        // Set when the decoder shrank the source: the intermediate nodes up to
        // the resize then describe a smaller image than their written meaning,
        // so they must not be shared with other consumers of this plan.
        var shrink: ShrinkOnLoad?
        if let image {
            current = image
        } else {
            let opened = try open(chain.source, planned: steps, context: context, label: label)
            current = opened.image
            shrink = opened.shrink
            if shareable && shrink == nil { context.remember(current, for: chain.sourceID) }
        }

        for index in next..<steps.count {
            try context.checkCancellation()
            let step = steps[index]
            if let rule = step.skippedBy {
                context.trace?.record(.operationSkipped(step.operation.name, rule))
            } else {
                let reference = shrink.flatMap { index == $0.resizeIndex ? $0.reference : nil }
                current = try apply(step.operation, to: current, reference: reference, context: context)
                context.trace?.record(.operationLowered(step.operation.name))
            }
            let sharesWrittenMeaning = shrink.map { index >= $0.resizeIndex } ?? true
            if shareable && sharesWrittenMeaning { context.remember(current, for: chain.steps[index].id) }
        }
        return current
    }

    /// A source opened at reduced size, and what the resize that follows needs.
    private struct ShrinkOnLoad {
        /// The planned step that resizes.
        let resizeIndex: Int
        /// The size the written pipeline sees at that step, before any shrink.
        let reference: (width: Int, height: Int)
    }

    /// Opens `source`, letting the decoder shrink it when the leading
    /// operations allow (see ``PlannerRule/shrinkOnLoad``).
    private static func open(
        _ source: ImageSource,
        planned steps: [PlannedStep],
        context: EvaluationContext,
        label: String
    ) throws -> (image: NativeImage, shrink: ShrinkOnLoad?) {
        let sequential = source.options.access == .sequential
        var native = try openUnshrunk(source, trace: context.trace)
        var shrink: ShrinkOnLoad?
        var shrinkFactor: Int?

        if context.planner.isEnabled(.shrinkOnLoad), source.options.page == nil, native.supportsDecoderShrink,
           let plan = shrinkPlan(for: native, steps: steps) {
            let reduced: NativeImage
            switch source {
            case .file(let url, let options): reduced = try NativeImage.open(path: url.path, options: options, decoderShrink: plan.factor)
            case .data(let data, let options): reduced = try NativeImage.open(data: data, options: options, decoderShrink: plan.factor)
            case .text: reduced = native
            }
            // The decoder may round a dimension up but never below what was
            // asked; if it did, keep the full-size source rather than resize
            // from fewer pixels than the written pipeline would have.
            if reduced.width >= plan.minimum.width, reduced.height >= plan.minimum.height {
                native = reduced
                shrink = ShrinkOnLoad(resizeIndex: plan.resizeIndex, reference: plan.reference)
                shrinkFactor = plan.factor
            }
        }
        context.trace?.record(.sourceOpened(label))
        if let shrinkFactor { context.trace?.record(.shrinkOnLoad(shrinkFactor)) }
        return (try context.watch(native, label: label, sequential: sequential), shrink)
    }

    private static func openUnshrunk(_ source: ImageSource, trace: PlanTrace?) throws -> NativeImage {
        switch source {
        case .file(let url, let options): try NativeImage.open(path: url.path, options: options)
        case .data(let data, let options): try NativeImage.open(data: data, options: options)
        case .text(let text): try NativeImage.renderText(text, trace: trace)
        }
    }

    /// Decides whether and how far the decoder may shrink `header`.
    ///
    /// Only `[autoOrient,] resize` may lead the pipeline. Shrinking changes
    /// pixels that an earlier operation (blur, extract, rotate) would have
    /// seen at full resolution, so any such operation rules it out.
    private static func shrinkPlan(
        for header: NativeImage,
        steps: [PlannedStep]
    ) -> (factor: Int, resizeIndex: Int, reference: (width: Int, height: Int), minimum: (width: Int, height: Int))? {
        var index = 0
        var oriented = false
        if index < steps.count, steps[index].skippedBy == nil, case .autoOrient = steps[index].operation {
            oriented = true
            index += 1
        }
        guard index < steps.count, steps[index].skippedBy == nil, case .resize(let resize) = steps[index].operation else {
            return nil
        }

        // The size the resize sees: orientations 5...8 swap the axes.
        let turned = oriented && header.exifOrientation >= 5
        let reference = turned ? (width: header.height, height: header.width) : (width: header.width, height: header.height)
        let target = NativeImage.proportionalSize(
            current: reference,
            target: (resize.width, resize.height),
            fit: resize.fit,
            withoutEnlargement: resize.withoutEnlargement,
            withoutReduction: resize.withoutReduction)

        // Back in the source's own axes, which is what the decoder shrinks.
        let needed = turned ? (width: target.height, height: target.width) : target
        for factor in [8, 4, 2] where
            ceilDiv(header.width, factor) >= needed.width && ceilDiv(header.height, factor) >= needed.height {
            return (factor, index, reference, needed)
        }
        return nil
    }

    private static func ceilDiv(_ value: Int, _ divisor: Int) -> Int { (value + divisor - 1) / divisor }

    private static func apply(
        _ operation: ImageOperation,
        to image: NativeImage,
        reference: (width: Int, height: Int)? = nil,
        context: EvaluationContext
    ) throws -> NativeImage {
        switch operation {
        case .autoOrient:
            return try image.autoOrient()

        case .resize(let step):
            return try image.resize(
                width: step.width,
                height: step.height,
                fit: step.fit,
                position: step.position,
                kernel: step.kernel,
                withoutEnlargement: step.withoutEnlargement,
                withoutReduction: step.withoutReduction,
                background: try step.background.rgba8(),
                reference: reference)

        case .rotate(let degrees, let background, let interpolation):
            return try image.rotate(degrees: degrees, background: try background.rgba8(), interpolation: interpolation)

        case .flip:
            return try image.mirrored(VIPS_DIRECTION_VERTICAL, operation: "flip")

        case .flop:
            return try image.mirrored(VIPS_DIRECTION_HORIZONTAL, operation: "flop")

        case .extract(let x, let y, let width, let height):
            return try image.crop(left: x, top: y, width: width, height: height)

        case .extend(let size, let anchor, let mode):
            return try image.extend(to: size, anchor: anchor, mode: mode)

        case .extendEdges(let top, let left, let bottom, let right, let mode):
            return try image.extend(top: top, left: left, bottom: bottom, right: right, mode: mode)

        case .affine(let step):
            return try image.affine(step)

        case .trim(let threshold):
            var left: Int32 = 0, top: Int32 = 0, width: Int32 = 0, height: Int32 = 0
            guard swift_vips_find_trim(image.pointer, &left, &top, &width, &height, threshold) == 0 else {
                throw HokusaiError.nativeTransform("trim")
            }
            return try image.crop(left: Int(left), top: Int(top), width: Int(width), height: Int(height))

        case .blur(let sigma, let precision, let minAmplitude):
            return try image.gaussianBlur(sigma: sigma, precision: precision, minAmplitude: minAmplitude)

        case .sharpen(let options):
            return try image.sharpen(options)

        case .grayscale:
            return try image.grayscaleEffect()

        case .convertToGrayscale:
            return try image.convertToGrayscale()

        case .tint(let color):
            return try image.tint(try color.rgba8())

        case .normalize(let lower, let upper):
            return try image.normalize(lower: lower, upper: upper)

        case .clahe(let width, let height, let maxSlope):
            return try image.clahe(width: width, height: height, maxSlope: maxSlope)

        case .gamma(let value):
            return try image.gamma(value)

        case .negate(let alpha):
            return try image.negate(alpha: alpha)

        case .median(let size):
            return try image.median(size: size)

        case .threshold(let level, let grayscale):
            return try image.threshold(level: level, grayscale: grayscale)

        case .modulate(let brightness, let saturation, let hue):
            return try image.modulate(brightness: brightness, saturation: saturation, hue: hue)

        case .convertToSRGB:
            return try image.applying("convert to sRGB") { swift_vips_colourspace_srgb($0, $1) }

        case .ensureAlpha(let opacity):
            return try image.ensureAlpha(opacity: opacity)

        case .removeAlpha:
            return try image.removeAlpha()

        case .flatten(let background):
            return try image.flatten(background: try background.rgba8())

        case .composite(let layers, let space):
            var native: [NativeLayer] = []
            for (index, layer) in layers.enumerated() {
                let scope = "composite layer \(index + 1)"
                do {
                    let overlay = try build(layer.plan, context: context, scope: scope)
                    native.append(NativeLayer(image: overlay, placement: layer.placement, blend: layer.blend, opacity: layer.opacity))
                } catch let error as HokusaiError {
                    throw error.scoped(scope)
                }
            }
            context.trace?.record(.compositeBlended(layers: native.count))
            return try image.composite(native, space: space)

        }
    }

    // MARK: - Helpers

    /// An encoder ready to run against any sink.
    enum SelectedEncoder {
        case raster(NativeEncoder)
        case pdf(PDFOptions)
    }

    /// Checks that this libvips build can encode `format` and lowers it once.
    ///
    /// Both terminals call this before any work, so a missing encoder gives
    /// the same typed error whether the destination is memory or a file.
    static func selectEncoder(
        _ format: OutputFormat,
        _ terminal: TerminalConfig,
        capabilities: @autoclosure () throws -> RuntimeCapabilities = try VipsRuntime.capabilities()
    ) throws -> SelectedEncoder {
        let available = try capabilities()
        guard available.canEncode(format.imageFormat) else {
            throw HokusaiError.unsupported(feature: "encoding \(format.imageFormat.rawValue)", reason: "not available in this libvips build")
        }
        if case .png(let options) = format, options.palette != nil, !available.pngPalette {
            throw HokusaiError.unsupported(
                feature: "palette PNG", reason: "this libvips build has no palette quantiser (libimagequant or quantizr)")
        }
        if case .heif(let options) = format, !available.canEncode(options.compression) {
            throw HokusaiError.unsupported(
                feature: "encoding HEIF with \(options.compression == .hevc ? "HEVC" : "AV1")",
                reason: "this libheif build has no encoder and decoder for that codec")
        }
        if case .pdf(let options) = format {
            return .pdf(options)
        }
        guard let encoder = NativeEncoder(format: format, metadata: terminal.metadataPolicy) else {
            throw HokusaiError.unsupported(feature: "encoding \(format.imageFormat.rawValue)", reason: "no raster encoder for this format")
        }
        return .raster(encoder)
    }
}
