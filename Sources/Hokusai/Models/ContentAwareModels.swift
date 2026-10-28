import Foundation

/// What `trim` treats as the border colour to remove.
public enum TrimBackground: Hashable, Sendable {
    /// The colour of the top-left pixel at the point the step runs.
    case topLeft
    /// An explicit colour. Needs a grey or RGB image.
    case color(Color)
}

/// Controls for ``Hokusai/trim(_:)``.
public struct TrimOptions: Hashable, Sendable {
    /// Tolerance for treating a pixel as background; lower removes only nearly identical borders.
    public var threshold: Double
    /// The border colour; defaults to the top-left pixel.
    public var background: TrimBackground
    /// Detects borders in line art and other synthetic images by looking for strong edges instead of colour differences.
    public var lineArt: Bool
    /// Pixels of the background to keep around the detected content, clamped to the image.
    public var margin: Int

    public init(threshold: Double = 10, background: TrimBackground = .topLeft, lineArt: Bool = false, margin: Int = 0) {
        self.threshold = threshold
        self.background = background
        self.lineArt = lineArt
        self.margin = margin
    }

    func validate() throws {
        guard threshold.isFinite, threshold >= 0 else {
            throw HokusaiError.invalidOption(name: "threshold", reason: "must be a finite value greater than or equal to zero")
        }
        guard (0...maximumNativeCoordinate).contains(margin) else {
            throw HokusaiError.invalidOption(name: "margin", reason: "must be in 0...\(maximumNativeCoordinate)")
        }
        if case .color(let color) = background { _ = try color.rgba8() }
    }
}

/// How ``Hokusai/smartCrop(width:height:strategy:)`` picks the region to keep.
public enum SmartCropStrategy: Hashable, Sendable {
    /// Favours skin tones, saturated colours and detail.
    case attention
    /// Favours the region with the most local variation.
    case entropy
}
