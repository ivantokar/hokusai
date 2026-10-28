import Foundation

/// Where a layer or generated overlay goes on its base image.
///
/// Exact coordinates and gravity are two spellings of the same thing: the
/// position of the layer's top-left corner. Positions may be negative or
/// reach past the base; libvips clips the layer to the base.
public enum Placement: Sendable, Hashable {
    /// The layer's top-left corner at exactly (`x`, `y`).
    case at(x: Int, y: Int)
    /// The layer anchored to a compass point of the base.
    ///
    /// Against an edge, the offset is padding towards the inside: for
    /// `.northWest` it moves right and down, for `.southEast` left and up.
    /// Along a centred axis it shifts the layer by the signed offset.
    case gravity(Gravity, offsetX: Int = 0, offsetY: Int = 0)
    /// The layer repeated edge to edge over the whole base, with one tile
    /// aligned to `gravity`. Meaningful for image layers only.
    case tile(gravity: Gravity = .northWest)
}

/// How a layer's pixels combine with what is below it.
///
/// The names follow the Porter-Duff and PDF blend sets that libvips
/// implements. `source` replaces what is below, `clear` erases it, and
/// `in`, `out`, `atop` keep only part of the layer or of the base depending
/// on the other side's alpha; `destination*` is the same set with the roles
/// swapped, and `xor` keeps each side only where the other is empty.
public enum BlendMode: Sendable, CaseIterable {
    case clear, source, over, `in`, out, atop
    case destination, destinationOver, destinationIn, destinationOut, destinationAtop
    case xor, add, saturate, multiply, screen, overlay, darken, lighten
    case colorDodge, colorBurn, hardLight, softLight, difference, exclusion
}

/// The colour space layers are blended in.
public enum CompositingSpace: Sendable {
    /// Blends the stored sRGB values, as design tools and browsers do.
    case srgb
    /// Blends linear light, which mixes colours the way light does. A 50%
    /// black layer over white comes out lighter than in `.srgb`.
    case linear
}

/// A layer composited over a pipeline in the supplied order.
///
/// A layer is another immutable pipeline. Only its image transformations
/// apply; its encoder and metadata settings are ignored, and it is never
/// encoded to be composed.
public struct CompositeLayer: Sendable {
    internal let source: Hokusai
    public let placement: Placement
    public let blend: BlendMode
    /// Multiplies the layer's alpha, `0...1`.
    public let opacity: Double

    /// Creates a layer from another immutable pipeline.
    public init(_ image: Hokusai, placement: Placement, blend: BlendMode = .over, opacity: Double = 1) {
        self.source = image
        self.placement = placement
        self.blend = blend
        self.opacity = opacity
    }

    /// Creates a layer whose top-left corner sits at (`x`, `y`).
    public init(_ image: Hokusai, x: Int = 0, y: Int = 0, blend: BlendMode = .over, opacity: Double = 1) {
        self.init(image, placement: .at(x: x, y: y), blend: blend, opacity: opacity)
    }
}
