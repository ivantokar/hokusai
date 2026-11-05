import Foundation

/// A convolution kernel: a small grid of coefficients slid over the image.
///
/// Each output sample is the sum of the neighbourhood weighted by ``values``, divided by
/// ``scale`` and increased by ``offset``, then limited to the sample range. `values` run
/// row by row, top to bottom. A kernel whose coefficients sum to 1 keeps overall brightness;
/// one that sums to 0 (edges, embossing) leaves flat areas black, so give it an ``offset``
/// to centre the result on mid grey, or take the absolute value of the response yourself.
///
/// ```swift
/// let sharpen = try ConvolutionKernel(width: 3, height: 3, values: [0, -1, 0, -1, 5, -1, 0, -1, 0])
/// let emboss = try ConvolutionKernel(width: 3, height: 3, values: [-2, -1, 0, -1, 1, 1, 0, 1, 2], offset: 128)
/// ```
public struct ConvolutionKernel: Sendable, Hashable {
    /// The largest side of a kernel, in coefficients.
    public static let maxSide = 51

    public let width: Int
    public let height: Int
    public let values: [Double]
    /// The divisor of the weighted sum. Never zero.
    public let scale: Double
    /// Added to the divided sum, on the 0...255 scale (16-bit images scale it).
    public let offset: Double

    /// - Throws: ``HokusaiError/invalidOption(name:reason:)`` when a side is outside
    ///   `1...51`, `values.count` is not `width × height`, a coefficient, `scale` or `offset`
    ///   is not finite, or `scale` is zero.
    public init(width: Int, height: Int, values: [Double], scale: Double = 1, offset: Double = 0) throws {
        for (name, side) in [("kernel width", width), ("kernel height", height)] where !(1...Self.maxSide).contains(side) {
            throw HokusaiError.invalidOption(name: name, reason: "must be in 1...\(Self.maxSide)")
        }
        guard values.count == width * height else {
            throw HokusaiError.invalidOption(name: "kernel values", reason: "expected \(width * height) coefficients for a \(width)×\(height) kernel, got \(values.count)")
        }
        guard values.allSatisfy(\.isFinite) else {
            throw HokusaiError.invalidOption(name: "kernel values", reason: "every coefficient must be finite")
        }
        guard scale.isFinite, scale != 0 else {
            throw HokusaiError.invalidOption(name: "kernel scale", reason: "must be finite and not zero")
        }
        guard offset.isFinite else {
            throw HokusaiError.invalidOption(name: "kernel offset", reason: "must be finite")
        }
        self.width = width
        self.height = height
        self.values = values
        self.scale = scale
        self.offset = offset
    }
}

/// A 3×3 colour matrix: each output colour is a weighted sum of the input's red, green and blue.
///
/// Rows are the output channels (red, green, blue) and columns the input channels, so the
/// identity is `[1, 0, 0, 0, 1, 0, 0, 0, 1]`. The weights are applied to sRGB values; an
/// image in another colour model is converted to sRGB first. Alpha is kept.
public struct ColorMatrix: Sendable, Hashable {
    /// Nine coefficients, row-major.
    public let values: [Double]

    /// The classic sepia tone.
    public static let sepia = ColorMatrix(unchecked: [
        0.393, 0.769, 0.189,
        0.349, 0.686, 0.168,
        0.272, 0.534, 0.131,
    ])

    /// Every channel becomes the Rec. 709 luminance, keeping three channels.
    public static let luminance = ColorMatrix(unchecked: [
        0.2126, 0.7152, 0.0722,
        0.2126, 0.7152, 0.0722,
        0.2126, 0.7152, 0.0722,
    ])

    /// Red and blue swapped.
    public static let swapRedBlue = ColorMatrix(unchecked: [0, 0, 1, 0, 1, 0, 1, 0, 0])

    private init(unchecked values: [Double]) {
        self.values = values
    }

    /// - Throws: ``HokusaiError/invalidOption(name:reason:)`` unless there are exactly nine
    ///   finite coefficients.
    public init(_ values: [Double]) throws {
        guard values.count == 9 else {
            throw HokusaiError.invalidOption(name: "color matrix", reason: "expected 9 coefficients (3×3), got \(values.count)")
        }
        guard values.allSatisfy(\.isFinite) else {
            throw HokusaiError.invalidOption(name: "color matrix", reason: "every coefficient must be finite")
        }
        self.values = values
    }
}

/// How ``Hokusai/edges(_:)`` measures where an image changes abruptly.
///
/// The result is the strength of the change in the image's luminance, as one channel:
/// bright where neighbouring pixels differ a lot, dark where they are alike. It is an
/// image-processing step, not object detection.
public enum EdgeDetector: Sendable, Hashable {
    /// The Sobel operator: a smoothed gradient, the usual choice.
    case sobel
    /// Scharr: like Sobel with a more rotation-invariant kernel.
    case scharr
    /// Prewitt: like Sobel with an unweighted average.
    case prewitt
    /// Canny: Gaussian smoothing of `sigma` pixels, then the gradient, thinned to a ridge.
    /// `sigma` must be finite and within `0.1...20`.
    case canny(sigma: Double = 1.4)
}

/// A channel of an image, named by what it means rather than by its band number.
public enum Channel: Sendable, Hashable, CaseIterable {
    case red, green, blue
    /// The alpha channel. An image without one cannot give it.
    case alpha
    /// Rec. 709 luminance of the colour channels.
    case luminance
}
