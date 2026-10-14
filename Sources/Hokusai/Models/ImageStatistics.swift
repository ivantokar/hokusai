import Foundation

/// Pixel statistics of a pipeline's current image.
///
/// Unlike ``ImageMetadata``, which reports what the source file said, these
/// facts come from the pixels the pipeline produces: `image.extract(...).stats()`
/// describes the crop. They are computed on 8-bit values (0...255), after the
/// image is converted to sRGB, or to grey when it is a greyscale image, so
/// they are comparable across source formats and bit depths. They are measured,
/// not read from a header, which means a full evaluation of the pipeline.
public struct ImageStatistics: Sendable, Equatable {
    /// One entry per band, in band order: grey, or red/green/blue, then alpha
    /// when the image has it.
    public let channels: [ChannelStatistics]

    /// Whether every pixel is fully opaque. Always true without an alpha band.
    public let isOpaque: Bool

    /// Shannon entropy in bits, from 0 for a single flat tone to 8 for an even
    /// spread across all 256 levels, of the 8-bit luminance. Alpha is ignored.
    public let entropy: Double

    /// The standard deviation of the 3 × 3 Laplacian of the 8-bit luminance.
    /// Higher means more edge detail. Alpha is ignored. It compares images of
    /// similar content and size, and is not a quality score: noise, texture,
    /// and fine detail all raise it. It is a floating-point sum computed on
    /// several threads, so repeated runs can differ in the last digits. Apart
    /// from tied extreme locations, every other field is exact.
    public let sharpness: Double

    /// The most common colour, as sRGB. Colours are grouped into 16 levels per
    /// channel and the centre of the fullest group is reported, so it is
    /// accurate to within about 8 of 255 per channel. Alpha is ignored, so
    /// transparent pixels count with their stored colour.
    public let dominantColor: Color?

    /// The channel for a band, or `nil` if the image has no such band.
    public func channel(_ kind: ChannelStatistics.Kind) -> ChannelStatistics? {
        channels.first { $0.kind == kind }
    }
}

/// Statistics of one band.
public struct ChannelStatistics: Sendable, Equatable {
    /// What a band holds.
    public enum Kind: Sendable, Equatable {
        case grey, red, green, blue, alpha
    }

    /// A pixel position, measured from the top left.
    public struct Location: Sendable, Equatable {
        public let x: Int
        public let y: Int
    }

    public let kind: Kind

    public let minimum: Double

    /// A pixel holding the minimum. When several pixels share it, which one is
    /// reported is not specified and can differ between runs.
    public let minimumLocation: Location

    public let maximum: Double

    /// A pixel holding the maximum, with the same caveat as ``minimumLocation``.
    public let maximumLocation: Location
    public let sum: Double
    public let sumOfSquares: Double
    public let mean: Double

    /// The sample standard deviation (dividing by n − 1), as libvips reports
    /// it, and 0 for an image of a single pixel.
    public let standardDeviation: Double
}
