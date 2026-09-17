import Foundation

/// The aspect-ratio policy for a resize with two target dimensions.
public enum ResizeFit: Sendable {
    /// Preserves aspect ratio while fitting entirely inside the target bounds.
    case inside

    /// Preserves aspect ratio while ensuring both dimensions meet the bounds.
    case outside

    /// Ignores aspect ratio and stretches to the exact target dimensions.
    case fill

    /// Preserves aspect ratio, then crops overflow to cover the target.
    case cover

    /// Preserves aspect ratio and pads remaining space with the background.
    case contain
}

/// An anchor or smart-crop strategy used by legacy resize and crop APIs.
public enum Position: Sendable {
    case center
    case top
    case bottom
    case left
    case right
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    /// Chooses the crop with the greatest visual information density.
    case entropy

    /// Chooses the crop around libvips' detected focal region.
    case attention
}

/// An interpolation kernel used when resampling an image.
public enum Kernel: String, Sendable {
    case nearest
    case linear
    case cubic
    case mitchell
    case lanczos2
    case lanczos3
}

/// The axis or axes used by a legacy flip operation.
public enum FlipDirection: Sendable {
    case horizontal
    case vertical
    case both
}

/// A right angle or an arbitrary rotation used by the native adapter.
public enum RotationAngle: Sendable {
    case degree90
    case degree180
    case degree270
    case custom(Double)

    var degrees: Double {
        switch self {
        case .degree90: return 90
        case .degree180: return 180
        case .degree270: return 270
        case .custom(let angle): return angle
        }
    }
}
