import Foundation

/// How the image should be resized to fit the target dimensions
public enum ResizeFit: Sendable {
    /// Preserving aspect ratio, resize to be as large as possible while ensuring dimensions are less than or equal to specified
    case inside

    /// Preserving aspect ratio, resize to be as small as possible while ensuring dimensions are greater than or equal to specified
    case outside

    /// Ignore aspect ratio, resize to exact dimensions
    case fill

    /// Preserving aspect ratio, resize and crop to cover the specified dimensions
    case cover

    /// Preserving aspect ratio, resize to fit within dimensions, padding with background color if needed
    case contain
}

/// Position for crop and cover operations
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

    /// Entropy-based crop (smart crop)
    case entropy

    /// Attention-based crop (focus on most important area)
    case attention
}

/// Interpolation kernel for resize operations
public enum Kernel: String, Sendable {
    case nearest
    case linear
    case cubic
    case mitchell
    case lanczos2
    case lanczos3
}

/// Direction for flip operation
public enum FlipDirection: Sendable {
    case horizontal
    case vertical
    case both
}

/// Angle for rotation
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
