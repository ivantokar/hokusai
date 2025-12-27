import Foundation
import CImageMagick

/// Text rendering operations using ImageMagick backend
extension HokusaiImage {
    /// Draw text on the image at specified position using ImageMagick
    ///
    /// This operation automatically switches to ImageMagick backend for advanced text rendering.
    ///
    /// Example:
    /// ```swift
    /// var options = TextOptions()
    /// options.font = "/path/to/font.ttf"
    /// options.fontSize = 96
    /// options.color = [0, 0, 128, 255]  // Navy blue
    /// options.strokeColor = [255, 255, 255, 255]  // White outline
    /// options.strokeWidth = 2.0
    ///
    /// let withText = try image.drawText("Hello World", x: 100, y: 200, options: options)
    /// ```
    public func drawText(
        _ text: String,
        x: Int,
        y: Int,
        options: TextOptions = TextOptions()
    ) throws -> HokusaiImage {
        // Switch to MagickBackend for text rendering
        let magickBackend = try ensureMagickBackend()

        // Perform text rendering (modifies the wand in place)
        try magickBackend.drawText(
            text,
            x: Double(x),
            y: Double(y),
            options: options
        )

        // Return self (magick backend is already updated)
        return self
    }

    /// Draw text with automatic positioning (e.g., top-left, bottom-right)
    ///
    /// Example:
    /// ```swift
    /// var options = TextOptions()
    /// options.fontSize = 48
    /// options.gravity = .center
    ///
    /// let withText = try image.drawText(
    ///     "Centered Text",
    ///     position: .center,
    ///     options: options
    /// )
    /// ```
    public func drawText(
        _ text: String,
        position: Position,
        options: TextOptions = TextOptions(),
        padding: Int = 10
    ) throws -> HokusaiImage {
        let imageWidth = try self.width
        let imageHeight = try self.height

        // Calculate position based on gravity/position
        let (x, y) = calculateTextPosition(
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            position: position,
            padding: padding,
            fontSize: options.fontSize
        )

        return try drawText(text, x: x, y: y, options: options)
    }

    // MARK: - Private Helpers

    private func calculateTextPosition(
        imageWidth: Int,
        imageHeight: Int,
        position: Position,
        padding: Int,
        fontSize: Int
    ) -> (x: Int, y: Int) {
        // Estimate text height based on fontSize
        let textHeight = fontSize

        switch position {
        case .center:
            return (imageWidth / 2, imageHeight / 2)
        case .top:
            return (imageWidth / 2, padding + textHeight)
        case .bottom:
            return (imageWidth / 2, imageHeight - padding)
        case .left:
            return (padding, imageHeight / 2)
        case .right:
            return (imageWidth - padding, imageHeight / 2)
        case .topLeft:
            return (padding, padding + textHeight)
        case .topRight:
            return (imageWidth - padding, padding + textHeight)
        case .bottomLeft:
            return (padding, imageHeight - padding)
        case .bottomRight:
            return (imageWidth - padding, imageHeight - padding)
        default:
            return (imageWidth / 2, imageHeight / 2)
        }
    }
}
