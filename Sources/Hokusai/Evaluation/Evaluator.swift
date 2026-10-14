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
            let data: Data
            switch encoder {
            case .pdf(let options): data = try image.pdf(options: options)
            case .raster(let encoder): data = try image.encoded(encoder)
            }
            return Output(data: data, info: OutputInfo(format: format.imageFormat, width: image.width, height: image.height, size: data.count))
        }
    }

    /// Evaluates `plan` and writes it to a local file.
    static func write(_ plan: ImagePlan, _ terminal: TerminalConfig, as format: OutputFormat, to url: URL, context: EvaluationContext) throws -> OutputInfo {
        let encoder = try selectEncoder(format, terminal)
        return try classifyingSourceFailures(in: context) {
            let image = try context.sink(for: build(plan, context: context, scope: nil))
            let size: Int
            switch encoder {
            case .pdf(let options):
                // PDF builds its document in memory until the Cairo stream
                // sink (#44) replaces this.
                context.trace?.record(.sinkSelected("memory pdf"))
                let document = try image.pdf(options: options)
                do {
                    try document.write(to: url)
                } catch {
                    throw HokusaiError.io(url: url, operation: .write, reason: error.localizedDescription)
                }
                size = document.count
            case .raster(let encoder):
                context.trace?.record(.sinkSelected("file \(format.imageFormat.rawValue)"))
                size = try image.write(encoder, to: url)
            }
            return OutputInfo(format: format.imageFormat, width: image.width, height: image.height, size: size)
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
        if let image {
            current = image
        } else {
            current = try open(chain.source, context: context, label: label)
            if shareable { context.remember(current, for: chain.sourceID) }
        }

        for index in next..<steps.count {
            try context.checkCancellation()
            let step = steps[index]
            if let rule = step.skippedBy {
                context.trace?.record(.operationSkipped(step.operation.name, rule))
            } else {
                current = try apply(step.operation, to: current, context: context)
                context.trace?.record(.operationLowered(step.operation.name))
            }
            if shareable { context.remember(current, for: chain.steps[index].id) }
        }
        return current
    }

    private static func open(_ source: ImageSource, context: EvaluationContext, label: String) throws -> NativeImage {
        let native: NativeImage
        switch source {
        case .file(let url, let options):
            native = try NativeImage.open(path: url.path, options: options)
        case .data(let data, let options):
            native = try NativeImage.open(data: data, options: options)
        }
        context.trace?.record(.sourceOpened(label))
        return try context.watch(native, label: label, sequential: source.options.access == .sequential)
    }

    private static func apply(_ operation: ImageOperation, to image: NativeImage, context: EvaluationContext) throws -> NativeImage {
        switch operation {
        case .autoOrient:
            return try image.autoRotate()

        case .resize(let step):
            var options = ResizeOptions()
            options.fit = step.fit
            options.position = step.position.legacyPosition
            options.kernel = step.kernel.legacyKernel
            options.withoutEnlargement = step.withoutEnlargement
            options.withoutReduction = step.withoutReduction
            options.background = try step.background.rgba8()
            return try image.resize(width: step.width, height: step.height, options: options)

        case .rotate(let degrees, let background):
            return try image.rotate(angle: .custom(degrees), background: try background.rgba8())

        case .flip:
            return try image.flip(direction: .vertical)

        case .flop:
            return try image.flip(direction: .horizontal)

        case .extract(let x, let y, let width, let height):
            return try image.crop(left: x, top: y, width: width, height: height)

        case .extend(let size, let anchor, let background):
            guard size.width >= image.width, size.height >= image.height else {
                throw HokusaiError.invalidOption(name: "size", reason: "extend cannot reduce an image; use resize or extract")
            }
            let offset = anchor.offset(imageWidth: image.width, imageHeight: image.height, canvasWidth: size.width, canvasHeight: size.height)
            return try withNativeColor(background, operation: "extend") { area in
                try image.applying("extend") { swift_vips_embed($0, $1, Int32(offset.x), Int32(offset.y), Int32(size.width), Int32(size.height), area) }
            }

        case .trim(let threshold):
            var left: Int32 = 0, top: Int32 = 0, width: Int32 = 0, height: Int32 = 0
            guard swift_vips_find_trim(image.pointer, &left, &top, &width, &height, threshold) == 0 else {
                throw HokusaiError.nativeTransform("trim")
            }
            return try image.crop(left: Int(left), top: Int(top), width: Int(width), height: Int(height))

        case .blur(let sigma):
            return try image.applying("blur") { swift_vips_gaussblur($0, $1, sigma) }

        case .sharpen(let sigma):
            return try image.applying("sharpen") { swift_vips_sharpen($0, $1, sigma) }

        case .grayscale:
            return try image.applying("grayscale") { swift_vips_colourspace_bw($0, $1) }

        case .tint(let color):
            let rgba = try color.rgba8()
            return try image.applying("tint") { swift_vips_tint($0, $1, rgba[0], rgba[1], rgba[2]) }

        case .normalize:
            return try image.applying("normalize") { swift_vips_hist_norm($0, $1) }

        case .convertToSRGB:
            return try image.applying("convert to sRGB") { swift_vips_colourspace_srgb($0, $1) }

        case .ensureAlpha:
            if image.hasAlpha { return image }
            return try image.applying("ensure alpha") { swift_vips_addalpha($0, $1) }

        case .flatten(let background):
            return try withNativeColor(background, operation: "flatten") { area in
                try image.applying("flatten") { swift_vips_flatten($0, $1, area) }
            }

        case .composite(let layers):
            var result = image
            for (index, layer) in layers.enumerated() {
                let scope = "composite layer \(index + 1)"
                let overlay: NativeImage
                do {
                    overlay = try build(layer.plan, context: context, scope: scope)
                } catch let error as HokusaiError {
                    throw error.scoped(scope)
                }
                result = try result.composite(
                    overlay: overlay,
                    x: layer.x,
                    y: layer.y,
                    options: CompositeOptions(mode: layer.blend, opacity: layer.opacity)
                )
            }
            return result

        case .drawText(let text, let x, let y, let options):
            return try image.drawText(text, x: x, y: y, options: options)
        }
    }

    // MARK: - Helpers

    /// Passes a native RGBA array to `body` and releases it afterwards.
    private static func withNativeColor<T>(
        _ color: Color,
        operation: String,
        _ body: (UnsafeMutablePointer<VipsArrayDouble>) throws -> T
    ) throws -> T {
        let rgba = try color.rgba8()
        let area = rgba.withUnsafeBufferPointer { swift_vips_array_double_new($0.baseAddress, Int32($0.count)) }
        guard let area else {
            throw HokusaiError.allocationFailed(operation)
        }
        defer { vips_area_unref(UnsafeMutablePointer(mutating: UnsafeRawPointer(area).assumingMemoryBound(to: VipsArea.self))) }
        return try body(area)
    }

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
        guard try capabilities().canEncode(format.imageFormat) else {
            throw HokusaiError.unsupported(feature: "encoding \(format.imageFormat.rawValue)", reason: "not available in this libvips build")
        }
        if case .pdf(let options) = format {
            return .pdf(options)
        }
        guard let encoder = NativeEncoder(format: format, preservesMetadata: terminal.preservesMetadata) else {
            throw HokusaiError.unsupported(feature: "encoding \(format.imageFormat.rawValue)", reason: "no raster encoder for this format")
        }
        return .raster(encoder)
    }
}
