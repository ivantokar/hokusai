import ArgumentParser
import Hokusai

struct AutoOrientStep: PipelineStep {
    static let name = "auto-orient"
    static let summary = "Apply the EXIF orientation to the pixels (autoOrient)."
    func apply(to image: Hokusai) throws -> Hokusai { image.autoOrient() }
}

struct ResizeStep: PipelineStep {
    static let name = "resize"
    static let summary = "Resize to a width, a height or both (resize)."

    @Option(help: "Target width.") var width: Int?
    @Option(help: "Target height.") var height: Int?
    @Option(help: "How the image meets the box: cover (default), contain, fill, inside or outside.") var fit = ResizeFitArgument.cover
    @Option(help: "Which part is kept by cover, or where contain places the image.") var position = PositionArgument.center
    @Option(help: "Resampling kernel.") var kernel = ResizeKernelArgument.lanczos3
    @Flag(help: "Never make the image larger.") var withoutEnlargement = false
    @Flag(help: "Never make the image smaller.") var withoutReduction = false
    @Option(help: "Padding colour of contain as r,g,b[,a] (0...255).", transform: ColorParser.parse) var background: Color = .transparent

    func validate() throws {
        guard width != nil || height != nil else { throw ValidationError("specify --width, --height, or both") }
    }

    func apply(to image: Hokusai) throws -> Hokusai {
        try image.resize(
            width: width, height: height, fit: fit.fit, position: position.position, kernel: kernel.kernel,
            withoutEnlargement: withoutEnlargement, withoutReduction: withoutReduction, background: background)
    }
}

struct RotateStep: PipelineStep {
    static let name = "rotate"
    static let summary = "Rotate by an angle in degrees (rotate)."

    @Option(help: "Angle in degrees, clockwise.") var degrees: Double
    @Option(help: "Fill of the corners as r,g,b[,a] (0...255).", transform: ColorParser.parse) var background: Color = .transparent
    @Option(help: "Interpolation for angles that are not multiples of 90.") var interpolation = InterpolationArgument.bilinear

    func apply(to image: Hokusai) throws -> Hokusai {
        try image.rotate(by: degrees, background: background, interpolation: interpolation.interpolation)
    }
}

struct FlipStep: PipelineStep {
    static let name = "flip"
    static let summary = "Mirror top to bottom (flip)."
    func apply(to image: Hokusai) throws -> Hokusai { image.flip() }
}

struct FlopStep: PipelineStep {
    static let name = "flop"
    static let summary = "Mirror left to right (flop)."
    func apply(to image: Hokusai) throws -> Hokusai { image.flop() }
}

struct ExtractStep: PipelineStep {
    static let name = "extract"
    static let summary = "Cut out a rectangle (extract)."

    @Option(help: "Left edge.") var x: Int
    @Option(help: "Top edge.") var y: Int
    @Option(help: "Width of the rectangle.") var width: Int
    @Option(help: "Height of the rectangle.") var height: Int

    func apply(to image: Hokusai) throws -> Hokusai { try image.extract(x: x, y: y, width: width, height: height) }
}

struct ExtendStep: PipelineStep {
    static let name = "extend"
    static let summary = "Add canvas around the image (extend)."

    @Option(help: "Grow to this total width (with --to-height).") var toWidth: Int?
    @Option(help: "Grow to this total height (with --to-width).") var toHeight: Int?
    @Option(help: "Where the image sits in the new canvas with --to-width.") var anchor = GravityArgument.center
    @Option(help: "Pixels to add above.") var top = 0
    @Option(help: "Pixels to add on the left.") var left = 0
    @Option(help: "Pixels to add below.") var bottom = 0
    @Option(help: "Pixels to add on the right.") var right = 0
    @Option(help: "How the new area is filled: background (default), copy, repeat or mirror.") var mode = EdgeModeArgument.background
    @Option(help: "Fill colour as r,g,b[,a] (0...255), for mode background.", transform: ColorParser.parse) var background: Color = .transparent

    func validate() throws {
        let byEdges = top != 0 || left != 0 || bottom != 0 || right != 0
        switch (toWidth, toHeight) {
        case (nil, nil): if !byEdges { throw ValidationError("give --to-width and --to-height, or --top, --left, --bottom or --right") }
        case (.some, .some): if byEdges { throw ValidationError("use --to-width and --to-height, or the edges, not both") }
        default: throw ValidationError("--to-width and --to-height go together")
        }
    }

    func apply(to image: Hokusai) throws -> Hokusai {
        let fill = mode.mode(background: background)
        if let toWidth, let toHeight {
            return try image.extend(to: ImageSize(width: toWidth, height: toHeight), anchor: anchor.gravity, mode: fill)
        }
        return try image.extend(top: top, left: left, bottom: bottom, right: right, mode: fill)
    }
}

struct AffineStep: PipelineStep {
    static let name = "affine"
    static let summary = "Apply a 2 x 2 matrix: rotate, scale and shear (affine)."

    @Option(help: "Matrix entry a.") var a = 1.0
    @Option(help: "Matrix entry b.") var b = 0.0
    @Option(help: "Matrix entry c.") var c = 0.0
    @Option(help: "Matrix entry d.") var d = 1.0
    @Option(help: "Input offset x.") var inputOffsetX = 0.0
    @Option(help: "Input offset y.") var inputOffsetY = 0.0
    @Option(help: "Output offset x.") var outputOffsetX = 0.0
    @Option(help: "Output offset y.") var outputOffsetY = 0.0
    @Option(help: "Output area as x,y,width,height.") var outputArea: String?
    @Option(help: "How pixels outside the source are filled: background (default), copy, repeat or mirror.") var edges = EdgeModeArgument.background
    @Option(help: "Fill colour for edges background, as r,g,b[,a] (0...255).", transform: ColorParser.parse) var background: Color = .transparent
    @Option(help: "Interpolation.") var interpolation = InterpolationArgument.bilinear

    func validate() throws {
        if let outputArea { _ = try Self.area(outputArea) }
    }

    private static func area(_ text: String) throws -> AffineArea {
        let parts = text.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 4, text.split(separator: ",").count == 4 else {
            throw ValidationError("--output-area is x,y,width,height as four integers, got '\(text)'")
        }
        return AffineArea(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    func apply(to image: Hokusai) throws -> Hokusai {
        try image.affine(
            AffineMatrix(a: a, b: b, c: c, d: d),
            inputOffset: AffineOffset(x: inputOffsetX, y: inputOffsetY),
            outputOffset: AffineOffset(x: outputOffsetX, y: outputOffsetY),
            outputArea: try outputArea.map(Self.area),
            edges: edges.mode(background: background),
            interpolation: interpolation.interpolation)
    }
}

struct TrimStep: PipelineStep {
    static let name = "trim"
    static let summary = "Cut away a uniform border (trim)."

    @Option(help: "How far a pixel may differ from the border colour and still be border.") var threshold = 10.0
    @Option(help: "Border colour as r,g,b[,a] (0...255); the top-left pixel when omitted.", transform: ColorParser.parse) var background: Color?
    @Flag(help: "Treat the image as line art.") var lineArt = false
    @Option(help: "Pixels of border to keep.") var margin = 0

    func apply(to image: Hokusai) throws -> Hokusai {
        try image.trim(TrimOptions(threshold: threshold, background: background.map { .color($0) } ?? .topLeft, lineArt: lineArt, margin: margin))
    }
}

struct SmartCropStep: PipelineStep {
    static let name = "smart-crop"
    static let summary = "Crop to the most interesting region (smartCrop)."

    @Option(help: "Width of the crop.") var width: Int
    @Option(help: "Height of the crop.") var height: Int
    @Option(help: "attention (default) or entropy.") var strategy = SmartCropStrategyArgument.attention

    func apply(to image: Hokusai) throws -> Hokusai { try image.smartCrop(width: width, height: height, strategy: strategy.strategy) }
}
