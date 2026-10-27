import Foundation
import CVips

/// Options for a legacy image-overlay operation.
public struct CompositeOptions: Sendable {
    /// The rule used to combine base and overlay pixels.
    public var mode: BlendMode

    /// Overlay opacity clamped to the range `0...1` during initialization.
    public var opacity: Double

    public init(
        mode: BlendMode = .over,
        opacity: Double = 1.0
    ) {
        self.mode = mode
        self.opacity = min(max(opacity, 0.0), 1.0)
    }
}

extension HokusaiImage {
    /// Draws `overlay` over this image at the supplied pixel offset.
    ///
    /// Example:
    /// ```swift
    /// let watermarked = try baseImage.composite(
    /// overlay: logoImage,
    /// x: 10,
    /// y: 10,
    /// options: CompositeOptions(mode: .over, opacity: 0.8)
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - overlay: The image to overlay on top
    ///   - x: Horizontal position (left edge of overlay)
    ///   - y: Vertical position (top edge of overlay)
    ///   - options: Composite options (blend mode, opacity)
    /// - Returns: New image with overlay composited
    public func composite(
        overlay: HokusaiImage,
        x: Int = 0,
        y: Int = 0,
        options: CompositeOptions = CompositeOptions()
    ) throws -> HokusaiImage {
        HokusaiImage(native: try native().composite(overlay: try overlay.native(), x: x, y: y, options: options))
    }
}

extension NativeImage {
    /// Draws `overlay` over this image at the supplied pixel offset.
    func composite(overlay: NativeImage, x: Int, y: Int, options: CompositeOptions) throws -> NativeImage {
        try composite(
            [NativeLayer(image: overlay, placement: .at(x: x, y: y), blend: options.mode, opacity: options.opacity)],
            space: .srgb
        )
    }
}
