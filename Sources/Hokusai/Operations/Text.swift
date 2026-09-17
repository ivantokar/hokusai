import Foundation
import CVips

/// Text rendering and composition backed by libvips and Pango.
extension HokusaiImage {
    /// Renders styled text and composites it onto this image.
    ///
    /// The rendering order is shadow, outline, then primary text. `x` and `y`
    /// are offsets from the top-left unless `options.gravity` supplies a
    /// semantic anchor. Layers that fall completely outside the base image are
    /// skipped rather than making a native composite call.
    ///
    /// ```swift
    /// let labelled = try image.drawText("Hello", x: 24, y: 24)
    /// ```
    public func drawText(
        _ text: String,
        x: Int,
        y: Int,
        options: TextOptions = TextOptions()
    ) throws -> HokusaiImage {
        let baseWidth = try self.width
        let baseHeight = try self.height

        var result = self
        let primaryOverlay = try buildTextOverlay(text: text, options: options, color: options.color)
        let rotatedPrimary = try maybeRotateTextLayer(primaryOverlay, options: options)

        let primaryWidth = try rotatedPrimary.width
        let primaryHeight = try rotatedPrimary.height
        let (baseX, baseY) = resolveTextOrigin(
            x: x,
            y: y,
            imageWidth: baseWidth,
            imageHeight: baseHeight,
            textWidth: primaryWidth,
            textHeight: primaryHeight,
            gravity: options.gravity
        )

        if let shadowOffset = options.shadowOffset {
            var shadowColor = normalizeRGBA(options.shadowColor ?? [0, 0, 0, 128])
            if let shadowOpacity = options.shadowOpacity {
                shadowColor[3] = min(max(shadowOpacity, 0.0), 1.0) * 255.0
            }

            var shadowOverlay = try buildTextOverlay(text: text, options: options, color: shadowColor)
            shadowOverlay = try maybeRotateTextLayer(shadowOverlay, options: options)
            shadowOverlay = try blurTextLayer(shadowOverlay, sigma: 1.2)
            let shadowWidth = try shadowOverlay.width
            let shadowHeight = try shadowOverlay.height
            let shadowX = baseX + Int(shadowOffset.x.rounded())
            let shadowY = baseY + Int(shadowOffset.y.rounded())

            if shouldComposite(
                overlayX: shadowX,
                overlayY: shadowY,
                overlayWidth: shadowWidth,
                overlayHeight: shadowHeight,
                baseWidth: baseWidth,
                baseHeight: baseHeight
            ) {
                result = try result.composite(
                    overlay: shadowOverlay,
                    x: shadowX,
                    y: shadowY
                )
            }
        }

        if let strokeColor = options.strokeColor, let strokeWidth = options.strokeWidth, strokeWidth > 0 {
            let strokeOverlay = try maybeRotateTextLayer(
                try buildTextOverlay(text: text, options: options, color: strokeColor),
                options: options
            )

            let radius = max(1, Int(strokeWidth.rounded()))
            for dy in -radius...radius {
                for dx in -radius...radius {
                    if dx == 0 && dy == 0 { continue }
                    if dx * dx + dy * dy > radius * radius { continue }
                    let strokeX = baseX + dx
                    let strokeY = baseY + dy

                    if !shouldComposite(
                        overlayX: strokeX,
                        overlayY: strokeY,
                        overlayWidth: primaryWidth,
                        overlayHeight: primaryHeight,
                        baseWidth: baseWidth,
                        baseHeight: baseHeight
                    ) {
                        continue
                    }

                    result = try result.composite(
                        overlay: strokeOverlay,
                        x: strokeX,
                        y: strokeY
                    )
                }
            }
        }

        if shouldComposite(
            overlayX: baseX,
            overlayY: baseY,
            overlayWidth: primaryWidth,
            overlayHeight: primaryHeight,
            baseWidth: baseWidth,
            baseHeight: baseHeight
        ) {
            result = try result.composite(overlay: rotatedPrimary, x: baseX, y: baseY)
        }
        return result
    }

    /// Draws text at a semantic image position with optional edge padding.
    public func drawText(
        _ text: String,
        position: Position,
        options: TextOptions = TextOptions(),
        padding: Int = 10
    ) throws -> HokusaiImage {
        let (gravity, x, y) = positionPlacement(position: position, padding: padding)
        var positionedOptions = options
        positionedOptions.gravity = gravity
        return try drawText(text, x: x, y: y, options: positionedOptions)
    }

    // MARK: - Private Helpers

    /// Renders one independent Pango-backed RGBA layer before compositing it.
    private func buildTextOverlay(
        text: String,
        options: TextOptions,
        color: [Double]
    ) throws -> HokusaiImage {
        // Render an independent RGBA layer. The caller decides where and in
        // which order it is composited with shadow and outline layers.
        var renderedText: UnsafeMutablePointer<CVips.VipsImage>?

        let (fontSpec, fontFile) = fontSpecAndFile(from: options)
        let align = mapTextAlignment(options.align)
        let spacing = computeLineSpacing(options)
        let pangoText = pangoMarkupText(text: text, color: normalizeRGBA(color))

        let result = fontSpec.withCString { fontPtr in
            pangoText.withCString { textPtr in
                if let fontFile {
                    return fontFile.withCString { fontFilePtr in
                        swift_vips_text_full_fontfile(
                            &renderedText,
                            textPtr,
                            fontPtr,
                            fontFilePtr,
                            Int32(options.width ?? 0),
                            Int32(options.height ?? 0),
                            Int32(options.dpi),
                            align,
                            Int32(spacing),
                            1
                        )
                    }
                }

                return swift_vips_text_full(
                    &renderedText,
                    textPtr,
                    fontPtr,
                    Int32(options.width ?? 0),
                    Int32(options.height ?? 0),
                    Int32(options.dpi),
                    align,
                    Int32(spacing),
                    1
                )
            }
        }

        guard result == 0, let renderedText else {
            VipsBackend.discardPartialImage(renderedText)
            throw HokusaiError.textRenderingFailed(VipsBackend.getLastError())
        }

        return HokusaiImage(backend: .vips(VipsBackend(takingOwnership: renderedText)))
    }

    /// Applies arbitrary rotation only when the caller requested a nonzero angle.
    private func maybeRotateTextLayer(_ image: HokusaiImage, options: TextOptions) throws -> HokusaiImage {
        guard let rotation = options.rotation, rotation != 0 else {
            return image
        }

        return try image.rotate(
            angle: .custom(rotation),
            background: [0, 0, 0, 0]
        )
    }

    /// Softens a shadow layer without altering the original text layer.
    private func blurTextLayer(_ image: HokusaiImage, sigma: Double) throws -> HokusaiImage {
        let pointer = try image.ensureVipsBackend().getPointer()
        var output: UnsafeMutablePointer<CVips.VipsImage>?

        let result = swift_vips_gaussblur(pointer, &output, sigma)
        guard result == 0, let out = output else {
            VipsBackend.discardPartialImage(output)
            throw HokusaiError.vipsError(VipsBackend.getLastError())
        }

        return HokusaiImage(backend: .vips(VipsBackend(takingOwnership: out)))
    }

    /// Converts a semantic gravity anchor and offsets into an absolute top-left origin.
    private func resolveTextOrigin(
        x: Int,
        y: Int,
        imageWidth: Int,
        imageHeight: Int,
        textWidth: Int,
        textHeight: Int,
        gravity: TextGravity?
    ) -> (Int, Int) {
        // Convert an anchor plus caller offsets into one absolute top-left point.
        guard let gravity else {
            return (x, y)
        }

        let anchor: (Int, Int)

        switch gravity {
        case .center:
            anchor = ((imageWidth - textWidth) / 2, (imageHeight - textHeight) / 2)
        case .north:
            anchor = ((imageWidth - textWidth) / 2, 0)
        case .south:
            anchor = ((imageWidth - textWidth) / 2, imageHeight - textHeight)
        case .east:
            anchor = (imageWidth - textWidth, (imageHeight - textHeight) / 2)
        case .west:
            anchor = (0, (imageHeight - textHeight) / 2)
        case .northEast:
            anchor = (imageWidth - textWidth, 0)
        case .northWest:
            anchor = (0, 0)
        case .southEast:
            anchor = (imageWidth - textWidth, imageHeight - textHeight)
        case .southWest:
            anchor = (0, imageHeight - textHeight)
        }

        return (anchor.0 + x, anchor.1 + y)
    }

    /// Maps Hokusai alignment names to the corresponding Pango/libvips values.
    private func mapTextAlignment(_ alignment: TextAlignment) -> VipsAlign {
        switch alignment {
        case .left: return VIPS_ALIGN_LOW
        case .center: return VIPS_ALIGN_CENTRE
        case .right: return VIPS_ALIGN_HIGH
        }
    }

    /// Translates a font-relative line-spacing multiplier into Pango spacing.
    private func computeLineSpacing(_ options: TextOptions) -> Int {
        guard let lineSpacing = options.lineSpacing else {
            return 0
        }

        let multiplier = max(0.0, lineSpacing)
        return Int((Double(options.fontSize) * (multiplier - 1.0)).rounded())
    }

    /// Separates a Pango font specification from an optional explicit font file.
    private func fontSpecAndFile(from options: TextOptions) -> (fontSpec: String, fontFile: String?) {
        let fontValue = options.font.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackFamily = "sans"
        let familyOrSpec = fontValue.isEmpty ? fallbackFamily : fontValue

        if let explicitFontFile = normalizedFontFilePath(options.fontFile) {
            let fontSpec = isFontFilePath(familyOrSpec)
                ? "\(fallbackFamily) \(options.fontSize)"
                : appendFontSizeIfMissing(familyOrSpec, size: options.fontSize)
            return (fontSpec, explicitFontFile)
        }

        if isFontFilePath(familyOrSpec) {
            return ("\(fallbackFamily) \(options.fontSize)", familyOrSpec)
        }

        return (appendFontSizeIfMissing(familyOrSpec, size: options.fontSize), nil)
    }

    /// Recognises the path-like font values accepted for legacy compatibility.
    private func isFontFilePath(_ value: String) -> Bool {
        return value.contains("/") || value.hasSuffix(".ttf") || value.hasSuffix(".otf") || value.hasSuffix(".ttc")
    }

    /// Treats blank font-file options as absent before passing them to libvips.
    private func normalizedFontFilePath(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    /// Adds a size to a font family only when the caller did not provide one.
    private func appendFontSizeIfMissing(_ fontSpec: String, size: Int) -> String {
        let trimmed = fontSpec.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "sans \(size)"
        }

        let parts = trimmed.split(separator: " ")
        if let last = parts.last, Double(last) != nil {
            return trimmed
        }
        return "\(trimmed) \(size)"
    }

    /// Pads, truncates, and clamps a caller colour to an RGBA 0...255 vector.
    private func normalizeRGBA(_ values: [Double]) -> [Double] {
        var rgba = values

        if rgba.count < 4 {
            rgba += Array(repeating: 255.0, count: 4 - rgba.count)
        }

        if rgba.count > 4 {
            rgba = Array(rgba.prefix(4))
        }

        return rgba.map { min(max($0, 0.0), 255.0) }
    }

    /// Escapes user text and wraps it in the Pango markup used to set RGBA colour.
    private func pangoMarkupText(text: String, color: [Double]) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")

        let r = Int(color[0].rounded())
        let g = Int(color[1].rounded())
        let b = Int(color[2].rounded())
        let a = Int(color[3].rounded())
        let hex = String(format: "#%02X%02X%02X%02X", r, g, b, a)

        return "<span foreground=\"\(hex)\">\(escaped)</span>"
    }

    /// Returns whether an overlay rectangle intersects the base image at all.
    private func shouldComposite(
        overlayX: Int,
        overlayY: Int,
        overlayWidth: Int,
        overlayHeight: Int,
        baseWidth: Int,
        baseHeight: Int
    ) -> Bool {
        let right = overlayX + overlayWidth
        let bottom = overlayY + overlayHeight
        return overlayX < baseWidth && overlayY < baseHeight && right > 0 && bottom > 0
    }

    /// Maps the legacy semantic position to a gravity anchor and signed padding.
    private func positionPlacement(
        position: Position,
        padding: Int
    ) -> (gravity: TextGravity, x: Int, y: Int) {
        switch position {
        case .center:
            return (.center, 0, 0)
        case .top:
            return (.north, 0, padding)
        case .bottom:
            return (.south, 0, -padding)
        case .left:
            return (.west, padding, 0)
        case .right:
            return (.east, -padding, 0)
        case .topLeft:
            return (.northWest, padding, padding)
        case .topRight:
            return (.northEast, -padding, padding)
        case .bottomLeft:
            return (.southWest, padding, -padding)
        case .bottomRight:
            return (.southEast, -padding, -padding)
        default:
            return (.center, 0, 0)
        }
    }
}
