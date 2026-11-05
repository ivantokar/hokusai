import ArgumentParser
import Foundation
import Hokusai

/// Comma-separated numbers: `0,-1,0,-1,5,-1,0,-1,0`. Write a list that starts with a minus as
/// `--values=-1,0,...` so the parser does not read it as an option.
struct NumberList: ExpressibleByArgument {
    let values: [Double]

    init?(argument: String) {
        let parts = argument.split(separator: ",", omittingEmptySubsequences: false).map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        values = parts.compactMap { $0 }
    }
}

enum EdgeDetectorArgument: String, CaseInsensitiveArgument {
    case sobel, scharr, prewitt, canny
}

enum ChannelArgument: String, CaseInsensitiveArgument {
    case red, green, blue, alpha, luminance

    var channel: Channel {
        switch self {
        case .red: .red
        case .green: .green
        case .blue: .blue
        case .alpha: .alpha
        case .luminance: .luminance
        }
    }
}

enum ColorMatrixPreset: String, CaseInsensitiveArgument {
    case sepia, luminance
    case swapRedBlue = "swap-red-blue"

    var matrix: ColorMatrix {
        switch self {
        case .sepia: .sepia
        case .luminance: .luminance
        case .swapRedBlue: .swapRedBlue
        }
    }
}

struct ConvolveStep: PipelineStep {
    static let name = "convolve"
    static let summary = "Convolve with a custom kernel (convolve)."

    @Option(help: "Kernel width in coefficients, 1...51.") var width: Int
    @Option(help: "Kernel height in coefficients, 1...51.") var height: Int
    @Option(help: "Coefficients, row by row, comma-separated. Start a list with a minus as --values=-1,0,...") var values: NumberList
    @Option(help: "Divisor of the weighted sum.") var scale = 1.0
    @Option(help: "Added after dividing, on the 0...255 scale.") var offset = 0.0

    func apply(to image: Hokusai) throws -> Hokusai {
        image.convolve(try ConvolutionKernel(width: width, height: height, values: values.values, scale: scale, offset: offset))
    }
}

struct LinearStep: PipelineStep {
    static let name = "linear"
    static let summary = "Multiply and add to the colour channels (linear)."

    @Option(help: "Factor, -1000...1000.") var multiply = 1.0
    @Option(help: "Amount added, on the 0...255 scale.") var add = 0.0

    func apply(to image: Hokusai) throws -> Hokusai { try image.linear(multiply: multiply, add: add) }
}

struct RecombineStep: PipelineStep {
    static let name = "recombine"
    static let summary = "Mix red, green and blue with a 3x3 matrix (recombine)."

    @Option(help: "A named matrix: sepia, luminance or swap-red-blue.") var preset: ColorMatrixPreset?
    @Option(help: "Nine coefficients, row by row (rows are output red, green, blue).") var matrix: NumberList?

    func validate() throws {
        guard (preset == nil) != (matrix == nil) else { throw ValidationError("give exactly one of --preset and --matrix") }
    }

    func apply(to image: Hokusai) throws -> Hokusai {
        if let preset { return image.recombine(preset.matrix) }
        return image.recombine(try ColorMatrix(matrix?.values ?? []))
    }
}

struct DilateStep: PipelineStep {
    static let name = "dilate"
    static let summary = "Grow bright areas (dilate)."

    @Option(help: "Radius of the square window, 1...50.") var radius = 1

    func apply(to image: Hokusai) throws -> Hokusai { try image.dilate(radius: radius) }
}

struct ErodeStep: PipelineStep {
    static let name = "erode"
    static let summary = "Shrink bright areas (erode)."

    @Option(help: "Radius of the square window, 1...50.") var radius = 1

    func apply(to image: Hokusai) throws -> Hokusai { try image.erode(radius: radius) }
}

struct EdgesStep: PipelineStep {
    static let name = "edges"
    static let summary = "Edge strength of the luminance (edges)."

    @Option(help: "sobel (default), scharr, prewitt or canny.") var detector = EdgeDetectorArgument.sobel
    @Option(help: "Smoothing in pixels, 0.1...20. Canny only (default 1.4).") var sigma: Double?

    func validate() throws {
        if sigma != nil, detector != .canny { throw ValidationError("--sigma applies to --detector canny only") }
    }

    func apply(to image: Hokusai) throws -> Hokusai {
        switch detector {
        case .sobel: try image.edges(.sobel)
        case .scharr: try image.edges(.scharr)
        case .prewitt: try image.edges(.prewitt)
        case .canny: try image.edges(.canny(sigma: sigma ?? 1.4))
        }
    }
}

struct ExtractChannelStep: PipelineStep {
    static let name = "extract-channel"
    static let summary = "Keep one channel as a grey image (extractChannel)."

    @Option(help: "red, green, blue, alpha or luminance.") var channel: ChannelArgument

    func apply(to image: Hokusai) throws -> Hokusai { image.extractChannel(channel.channel) }
}

struct WithAlphaStep: PipelineStep {
    static let name = "with-alpha"
    static let summary = "Use another image's luminance as the alpha channel (withAlpha)."

    @Option(help: "Path of the mask image; it must be the same size.") var mask: String

    func apply(to image: Hokusai) throws -> Hokusai {
        image.withAlpha(from: try Hokusai(url: URL(fileURLWithPath: mask)))
    }
}
