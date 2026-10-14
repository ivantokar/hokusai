import Foundation

/// Immutable description of the image a pipeline produces.
///
/// A plan is a source followed by ordered operations. Composite layers hold
/// their own plans, so the structure is a DAG. Every step is an immutable
/// node, and branching a pipeline shares its prefix nodes without copying;
/// encoded `Data` sources are shared copy-on-write. Node identity is what
/// lets one evaluation build a shared subplan once (see ``Evaluator``).
/// Nothing here touches libvips.
struct ImagePlan: Sendable {
    private let node: Node

    private init(node: Node) {
        self.node = node
    }

    /// A plan that is just `source`.
    static func source(_ source: ImageSource) -> ImagePlan {
        ImagePlan(node: Node(source: source))
    }

    /// Returns a plan that applies `operation` after this one.
    func appending(_ operation: ImageOperation) -> ImagePlan {
        ImagePlan(node: Node(operation: operation, input: node))
    }

    /// The source and operations in evaluation order.
    var linearized: (source: ImageSource, operations: [ImageOperation]) {
        let chain = self.chain
        return (chain.source, chain.steps.map(\.operation))
    }

    /// The source and each step with the identity of the node it produces.
    ///
    /// Walking iteratively keeps long chains from growing the call stack.
    var chain: Chain {
        var steps: [Chain.Step] = []
        var current = node
        while true {
            switch current.kind {
            case .source(let source):
                return Chain(source: source, sourceID: ObjectIdentifier(current), steps: steps.reversed())
            case .apply(let operation, let input):
                steps.append(Chain.Step(id: ObjectIdentifier(current), operation: operation))
                current = input
            }
        }
    }

    /// A plan flattened from source to result.
    struct Chain {
        struct Step {
            /// Identifies the node whose result is the image after `operation`.
            let id: ObjectIdentifier
            let operation: ImageOperation
        }

        let source: ImageSource
        /// Identifies the source node, shared by every plan derived from it.
        let sourceID: ObjectIdentifier
        let steps: [Step]
    }

    private final class Node: Sendable {
        enum Kind: Sendable {
            case source(ImageSource)
            case apply(ImageOperation, input: Node)
        }

        let kind: Kind

        init(source: ImageSource) {
            kind = .source(source)
        }

        init(operation: ImageOperation, input: Node) {
            kind = .apply(operation, input: input)
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
    var metadataPolicy = MetadataPolicy.default
}
