import ArgumentParser
import Foundation
import Hokusai

struct BlurStep: PipelineStep {
    static let name = "blur"
    static let summary = "Gaussian blur (blur)."

    @Option(help: "Standard deviation of the blur.") var sigma = 1.0
    @Option(help: "integer (default), float or approximate.") var precision = BlurPrecisionArgument.integer
    @Option(help: "Smallest amplitude the kernel keeps.") var minAmplitude = 0.2

    func apply(to image: Hokusai) throws -> Hokusai { try image.blur(sigma: sigma, precision: precision.precision, minAmplitude: minAmplitude) }
}

struct SharpenStep: PipelineStep {
    static let name = "sharpen"
    static let summary = "Sharpen (sharpen)."

    @Option(help: "Standard deviation of the sharpening.") var sigma = 1.0
    @Option(help: "Sharpening of flat areas.") var flat: Double?
    @Option(help: "Sharpening of jagged areas.") var jagged: Double?
    @Option(help: "Level below which nothing is sharpened.") var threshold: Double?
    @Option(help: "Largest brightening.") var maxBrightening: Double?
    @Option(help: "Largest darkening.") var maxDarkening: Double?

    func apply(to image: Hokusai) throws -> Hokusai {
        var options = SharpenOptions(sigma: sigma)
        if let flat { options.flat = flat }
        if let jagged { options.jagged = jagged }
        if let threshold { options.threshold = threshold }
        if let maxBrightening { options.maxBrightening = maxBrightening }
        if let maxDarkening { options.maxDarkening = maxDarkening }
        return try image.sharpen(options)
    }
}

struct GrayscaleStep: PipelineStep {
    static let name = "grayscale"
    static let summary = "Desaturate, keeping the RGB layout (grayscale)."
    func apply(to image: Hokusai) throws -> Hokusai { image.grayscale() }
}

struct TintStep: PipelineStep {
    static let name = "tint"
    static let summary = "Tint with a colour (tint)."

    @Option(help: "Tint colour as r,g,b[,a] (0...255).", transform: ColorParser.parse) var color: Color

    func apply(to image: Hokusai) throws -> Hokusai { try image.tint(color) }
}

struct NormalizeStep: PipelineStep {
    static let name = "normalize"
    static let summary = "Stretch the contrast between two percentiles (normalize)."

    @Option(help: "Lower percentile.") var lower = 1.0
    @Option(help: "Upper percentile.") var upper = 99.0

    func apply(to image: Hokusai) throws -> Hokusai { try image.normalize(lower: lower, upper: upper) }
}

struct ClaheStep: PipelineStep {
    static let name = "clahe"
    static let summary = "Local contrast enhancement of the lightness (clahe)."

    @Option(help: "Tile width in pixels.") var width = 8
    @Option(help: "Tile height in pixels.") var height = 8
    @Option(help: "Limit of the contrast a tile may gain; 0 for none.") var maxSlope = 3

    func apply(to image: Hokusai) throws -> Hokusai { try image.clahe(width: width, height: height, maxSlope: maxSlope) }
}

struct GammaStep: PipelineStep {
    static let name = "gamma"
    static let summary = "Gamma correction (gamma)."

    @Option(help: "Gamma; values above 1 brighten.") var value = 2.2

    func apply(to image: Hokusai) throws -> Hokusai { try image.gamma(value) }
}

struct NegateStep: PipelineStep {
    static let name = "negate"
    static let summary = "Invert the colours (negate)."

    @Flag(help: "Invert alpha too.") var alpha = false

    func apply(to image: Hokusai) throws -> Hokusai { image.negate(alpha: alpha) }
}

struct MedianStep: PipelineStep {
    static let name = "median"
    static let summary = "Median filter (median)."

    @Option(help: "Window size.") var size = 3

    func apply(to image: Hokusai) throws -> Hokusai { try image.median(size: size) }
}

struct ThresholdStep: PipelineStep {
    static let name = "threshold"
    static let summary = "Black and white at a level (threshold)."

    @Option(help: "Level on 0...255.") var level = 128.0
    @Flag(help: "Threshold each colour band instead of the luminance.") var perBand = false

    func apply(to image: Hokusai) throws -> Hokusai { try image.threshold(level, grayscale: !perBand) }
}

struct ModulateStep: PipelineStep {
    static let name = "modulate"
    static let summary = "Brightness, saturation and hue (modulate)."

    @Option(help: "Brightness multiplier.") var brightness = 1.0
    @Option(help: "Saturation multiplier.") var saturation = 1.0
    @Option(help: "Hue rotation in degrees. Write a negative value as --hue=-30.") var hue = 0.0

    func apply(to image: Hokusai) throws -> Hokusai { try image.modulate(brightness: brightness, saturation: saturation, hue: hue) }
}

struct ConvertToStep: PipelineStep {
    static let name = "convert-to"
    static let summary = "Change the colour space: srgb or grayscale (convert(to:))."

    @Option(help: "srgb or grayscale.") var space: ColorSpaceArgument

    func apply(to image: Hokusai) throws -> Hokusai { try image.convert(to: space.space) }
}

struct EnsureAlphaStep: PipelineStep {
    static let name = "ensure-alpha"
    static let summary = "Add an alpha band if there is none (ensureAlpha)."

    @Option(help: "Opacity of the added band, 0...1.") var opacity = 1.0

    func apply(to image: Hokusai) throws -> Hokusai { try image.ensureAlpha(opacity: opacity) }
}

struct FlattenStep: PipelineStep {
    static let name = "flatten"
    static let summary = "Composite onto a background and drop alpha (flatten)."

    @Option(help: "Background as r,g,b[,a] (0...255); white by default.", transform: ColorParser.parse) var background: Color = .white

    func apply(to image: Hokusai) throws -> Hokusai { try image.flatten(background: background) }
}

struct RemoveAlphaStep: PipelineStep {
    static let name = "remove-alpha"
    static let summary = "Drop the alpha band without compositing (removeAlpha)."
    func apply(to image: Hokusai) throws -> Hokusai { image.removeAlpha() }
}

struct CompositeStep: PipelineStep {
    static let name = "composite"
    static let summary = "Place another image on top (composite). Repeat the step for more layers."

    @Option(help: "Path of the overlay image.") var overlay: String
    @OptionGroup var placement: PlacementOptions
    @Option(help: "Blend mode, e.g. over (default), multiply, screen, soft-light.") var blend = BlendArgument(.over)
    @Option(help: "Multiplies the overlay's alpha, 0...1.") var opacity = 1.0
    @Option(help: "Blend in srgb (default) or linear light.") var space = CompositingSpaceArgument.srgb

    func apply(to image: Hokusai) throws -> Hokusai {
        let layer = CompositeLayer(try Hokusai(url: URL(fileURLWithPath: overlay)), placement: placement.placement, blend: blend.mode, opacity: opacity)
        return try image.composite([layer], space: space.space)
    }
}

struct DrawTextStep: PipelineStep {
    static let name = "draw-text"
    static let summary = "Draw text onto the image (drawText)."

    @Option(help: "Text to draw (plain content).") var text: String?
    @Option(help: "Pango markup to draw.") var markup: String?
    @OptionGroup var placement: PlacementOptions
    @OptionGroup(title: "Text options") var typography: TextStyleOptions

    func validate() throws {
        guard (text == nil) != (markup == nil) else { throw ValidationError("give exactly one of --text and --markup") }
    }

    func apply(to image: Hokusai) throws -> Hokusai {
        let content: TextContent = text.map { .plain($0) } ?? .markup(markup ?? "")
        return try image.drawText(content, placement: placement.placement, layout: typography.layout, style: typography.style)
    }
}
