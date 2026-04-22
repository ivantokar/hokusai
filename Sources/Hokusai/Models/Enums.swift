import Foundation

/// PURPOSE: How the image should be resized to fit the target dimensions
public enum ResizeFit: Sendable {
    /// PURPOSE: Preserving aspect ratio, resize to be as large as possible while ensuring dimensions are less than or equal to specified
    case inside

    /// PURPOSE: Preserving aspect ratio, resize to be as small as possible while ensuring dimensions are greater than or equal to specified
    case outside

    /// PURPOSE: Ignore aspect ratio, resize to exact dimensions
    case fill

    /// PURPOSE: Preserving aspect ratio, resize and crop to cover the specified dimensions
    case cover

    /// PURPOSE: Preserving aspect ratio, resize to fit within dimensions, padding with background color if needed
    case contain
}

/// PURPOSE: Position for crop and cover operations
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

    /// PURPOSE: Entropy-based crop (smart crop)
    case entropy

    /// PURPOSE: Attention-based crop (focus on most important area)
    case attention
}

/// PURPOSE: Interpolation kernel for resize operations
public enum Kernel: String, Sendable {
    case nearest
    case linear
    case cubic
    case mitchell
    case lanczos2
    case lanczos3
}

/// PURPOSE: Direction for flip operation
public enum FlipDirection: Sendable {
    case horizontal
    case vertical
    case both
}

/// PURPOSE: Angle for rotation
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
