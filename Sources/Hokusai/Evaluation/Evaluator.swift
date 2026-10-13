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
        let (source, operations) = plan.linearized
        try context.checkCancellation()
        var image = try open(source)
        for operation in operations {
            try context.checkCancellation()
            image = try apply(operation, to: image, context: context)
        }
        return image
    }

    /// Evaluates `plan` and returns encoded bytes.
    static func encode(_ plan: ImagePlan, _ terminal: TerminalConfig, as format: OutputFormat, context: EvaluationContext) throws -> Output {
        try requireEncoder(format)
        let image = try context.sink(for: lower(plan, context: context))
        let data: Data
        switch format {
        case .pdf(let options):
            data = try image.pdf(options: options)
        default:
            data = try image.encoded(options: saveOptions(format, terminal))
        }
        return Output(data: data, info: OutputInfo(format: format.imageFormat, width: image.width, height: image.height, size: data.count))
    }

    /// Evaluates `plan` and writes it to a local file.
    static func write(_ plan: ImagePlan, _ terminal: TerminalConfig, as format: OutputFormat, to url: URL, context: EvaluationContext) throws -> OutputInfo {
        try requireEncoder(format)
        let image = try context.sink(for: lower(plan, context: context))
        switch format {
        case .pdf(let options):
            let document = try image.pdf(options: options)
            do {
                try document.write(to: url)
            } catch {
                throw HokusaiError.io(url: url, operation: .write, reason: error.localizedDescription)
            }
        default:
            try image.write(to: url.path, options: saveOptions(format, terminal))
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return OutputInfo(format: format.imageFormat, width: image.width, height: image.height, size: size)
    }

    // MARK: - Lowering

    private static func open(_ source: ImageSource) throws -> NativeImage {
        switch source {
        case .file(let url):
            return try NativeImage.open(path: url.path)
        case .data(let data):
            return try NativeImage.open(data: data)
        }
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
                let overlay: NativeImage
                do {
                    overlay = try lower(layer.plan, context: context)
                } catch let error as HokusaiError {
                    throw error.scoped("composite layer \(index + 1)")
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

    /// Rejects encoders this libvips build lacks before doing any work.
    private static func requireEncoder(_ format: OutputFormat) throws {
        guard try VipsRuntime.capabilities().canEncode(format.imageFormat) else {
            throw HokusaiError.unsupported(feature: "encoding \(format.imageFormat.rawValue)", reason: "not available in this libvips build")
        }
    }

    private static func saveOptions(_ format: OutputFormat, _ terminal: TerminalConfig) -> SaveOptions {
        var options = format.legacySaveOptions
        options.stripMetadata = !terminal.preservesMetadata
        return options
    }
}
