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
