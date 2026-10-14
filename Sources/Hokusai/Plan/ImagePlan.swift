import Foundation

/// Immutable description of the image a pipeline produces.
///
/// A plan is a source followed by ordered operations. Composite layers hold
/// their own plans, so the structure is a DAG. Indirect payloads are shared
/// immutable boxes: branching a pipeline shares its prefix without copying,
/// and encoded `Data` sources are shared copy-on-write. Nothing here touches
/// libvips; ``Evaluator`` lowers a plan to a native graph at terminal time.
indirect enum ImagePlan: Sendable {
    case source(ImageSource)
    case apply(ImageOperation, to: ImagePlan)

    /// Returns a plan that applies `operation` after this one.
    func appending(_ operation: ImageOperation) -> ImagePlan {
        .apply(operation, to: self)
    }

    /// The source and operations in evaluation order.
    ///
    /// Walking iteratively keeps long chains from growing the call stack.
    var linearized: (source: ImageSource, operations: [ImageOperation]) {
        var operations: [ImageOperation] = []
        var current = self
        while true {
            switch current {
            case .source(let source):
                return (source, operations.reversed())
            case .apply(let operation, let input):
                operations.append(operation)
                current = input
            }
        }
    }
}

/// Where a plan's pixels come from. The source stays unopened until lowering.
enum ImageSource: Sendable {
    /// A local file, opened at evaluation time.
    case file(URL, InputOptions)
    /// Owned encoded bytes, shared copy-on-write between branches.
    case data(Data, InputOptions)

    var options: InputOptions {
        switch self {
        case .file(_, let options), .data(_, let options): options
        }
    }

    /// The operation label for decoding this source.
    var decodeLabel: String {
        switch self {
        case .file(let url, _): "decode \(url.lastPathComponent)"
        case .data: "decode input data"
        }
    }
}

/// One image-producing step of a plan.
///
/// Options are validated when the step is appended; values that depend on
/// pixels (current size, alpha) are resolved during lowering.
enum ImageOperation: Sendable {
    case autoOrient
    case resize(ResizeStep)
    case rotate(degrees: Double, background: Color)
    case flip
    case flop
    case extract(x: Int, y: Int, width: Int, height: Int)
    case extend(to: ImageSize, anchor: CanvasAnchor, background: Color)
    case trim(threshold: Double)
    case blur(sigma: Double)
    case sharpen(sigma: Double)
    case grayscale
    case tint(Color)
    case normalize
    case convertToSRGB
    case ensureAlpha
    case flatten(background: Color)
    case composite([LayerStep])
    case drawText(String, x: Int, y: Int, options: TextOptions)

    /// The operation name used in typed error contexts.
    var name: String {
        switch self {
        case .autoOrient: "auto orient"
        case .resize: "resize"
        case .rotate: "rotate"
        case .flip: "flip"
        case .flop: "flop"
        case .extract: "extract"
        case .extend: "extend"
        case .trim: "trim"
        case .blur: "blur"
        case .sharpen: "sharpen"
        case .grayscale: "grayscale"
        case .tint: "tint"
        case .normalize: "normalize"
        case .convertToSRGB: "convert to sRGB"
        case .ensureAlpha: "ensure alpha"
        case .flatten: "flatten"
        case .composite: "composite layer"
        case .drawText: "draw text"
        }
    }
}

/// Resize intent kept in public vocabulary so later planning (#20) can
/// inspect it before choosing a loader.
struct ResizeStep: Sendable {
    var width: Int?
    var height: Int?
    var fit: ResizeFit
    var position: ResizePosition
    var kernel: ResizeKernel
    var withoutEnlargement: Bool
    var withoutReduction: Bool
    var background: Color
}

/// A composite layer: only the layer's image plan, never its terminal
/// configuration, so a layer's encoder cannot cause an intermediate encode.
struct LayerStep: Sendable {
    var plan: ImagePlan
    var x: Int
    var y: Int
    var blend: BlendMode
    var opacity: Double
}

/// Output configuration applied only by a terminal method.
struct TerminalConfig: Sendable {
    var encoder: OutputFormat?
    var preservesMetadata = false
}
