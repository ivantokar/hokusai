import Foundation
import CVips

/// Lowers immutable plans to libvips graphs and drives terminal sinks.
///
/// Every method performs native work and must run inside the terminal
/// execution boundary (`PipelineExecutor`, replaced by #41). Composite layers
/// are lowered within the same call; the evaluator never schedules work.
/// libvips stays the pixel engine: lowering only builds its lazy graph, and
/// pixels are computed when a sink pulls them.
enum Evaluator {
    /// Builds the native image graph described by `plan`.
    static func lower(_ plan: ImagePlan) throws -> NativeImage {
        let (source, operations) = plan.linearized
        var image = try open(source)
        for operation in operations {
            do {
                image = try apply(operation, to: image)
            } catch {
                throw HokusaiError.pipeline(error, operation: operation.name, category: .transform)
            }
        }
        return image
    }

    /// Evaluates `plan` and returns encoded bytes.
    static func encode(_ plan: ImagePlan, _ terminal: TerminalConfig, as format: OutputFormat) throws -> Output {
        let image = try lower(plan)
        do {
            let data: Data
            switch format {
            case .pdf(let options):
                data = try image.pdf(options: options)
            default:
                data = try image.encoded(options: saveOptions(format, terminal))
            }
            return Output(data: data, info: OutputInfo(format: format.imageFormat, width: image.width, height: image.height, size: data.count))
        } catch {
            throw HokusaiError.pipeline(error, operation: "encode \(format.imageFormat.rawValue)", category: .encode)
        }
    }

    /// Evaluates `plan` and writes it to a local file.
    static func write(_ plan: ImagePlan, _ terminal: TerminalConfig, as format: OutputFormat, to url: URL) throws -> OutputInfo {
        let image = try lower(plan)
        do {
            switch format {
            case .pdf(let options):
                try image.pdf(options: options).write(to: url)
            default:
                try image.write(to: url.path, options: saveOptions(format, terminal))
            }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return OutputInfo(format: format.imageFormat, width: image.width, height: image.height, size: size)
        } catch {
            throw HokusaiError.pipeline(error, operation: "write \(format.imageFormat.rawValue)", category: .encode)
        }
    }

    // MARK: - Lowering

    private static func open(_ source: ImageSource) throws -> NativeImage {
        switch source {
        case .file(let url):
            do {
                return try NativeImage.open(path: url.path)
            } catch {
                throw HokusaiError.pipeline(error, operation: "decode \(url.lastPathComponent)", category: .decode)
            }
        case .data(let data):
            do {
                return try NativeImage.open(data: data)
            } catch {
                throw HokusaiError.pipeline(error, operation: "decode input data", category: .decode)
            }
        }
    }

    private static func apply(_ operation: ImageOperation, to image: NativeImage) throws -> NativeImage {
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
                try image.applying({ swift_vips_embed($0, $1, Int32(offset.x), Int32(offset.y), Int32(size.width), Int32(size.height), area) }, failure: transformFailure("extend"))
            }

        case .trim(let threshold):
            var left: Int32 = 0, top: Int32 = 0, width: Int32 = 0, height: Int32 = 0
            guard swift_vips_find_trim(image.pointer, &left, &top, &width, &height, threshold) == 0 else {
                throw HokusaiError.transform(.init(operation: "trim", message: VipsBackend.getLastError()))
            }
            return try image.crop(left: Int(left), top: Int(top), width: Int(width), height: Int(height))

        case .blur(let sigma):
            return try image.applying({ swift_vips_gaussblur($0, $1, sigma) }, failure: transformFailure("blur"))

        case .sharpen(let sigma):
            return try image.applying({ swift_vips_sharpen($0, $1, sigma) }, failure: transformFailure("sharpen"))

        case .grayscale:
            return try image.applying({ swift_vips_colourspace_bw($0, $1) }, failure: transformFailure("grayscale"))

        case .tint(let color):
            let rgba = try color.rgba8()
            return try image.applying({ swift_vips_tint($0, $1, rgba[0], rgba[1], rgba[2]) }, failure: transformFailure("tint"))

        case .normalize:
            return try image.applying({ swift_vips_hist_norm($0, $1) }, failure: transformFailure("normalize"))

        case .convertToSRGB:
            return try image.applying({ swift_vips_colourspace_srgb($0, $1) }, failure: transformFailure("convert to sRGB"))

        case .ensureAlpha:
            if image.hasAlpha { return image }
            return try image.applying({ swift_vips_addalpha($0, $1) }, failure: transformFailure("ensure alpha"))

        case .flatten(let background):
            return try withNativeColor(background, operation: "flatten") { area in
                try image.applying({ swift_vips_flatten($0, $1, area) }, failure: transformFailure("flatten"))
            }

        case .composite(let layers):
            var result = image
            for layer in layers {
                result = try result.composite(
                    overlay: try lower(layer.plan),
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

    private static func transformFailure(_ operation: String) -> (String) -> HokusaiError {
        { HokusaiError.transform(.init(operation: operation, message: $0)) }
    }

    /// Passes a native RGBA array to `body` and releases it afterwards.
    private static func withNativeColor<T>(
        _ color: Color,
        operation: String,
        _ body: (UnsafeMutablePointer<VipsArrayDouble>) throws -> T
    ) throws -> T {
        let rgba = try color.rgba8()
        let area = rgba.withUnsafeBufferPointer { swift_vips_array_double_new($0.baseAddress, Int32($0.count)) }
        guard let area else {
            throw HokusaiError.runtime(.init(operation: operation, message: "could not allocate native background colour"))
        }
        defer { vips_area_unref(UnsafeMutablePointer(mutating: UnsafeRawPointer(area).assumingMemoryBound(to: VipsArea.self))) }
        return try body(area)
    }

    private static func saveOptions(_ format: OutputFormat, _ terminal: TerminalConfig) -> SaveOptions {
        var options = format.legacySaveOptions
        options.stripMetadata = !terminal.preservesMetadata
        return options
    }
}
