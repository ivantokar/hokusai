import Foundation
import CVips

// MARK: - Rendering

extension TextWrap {
    fileprivate var vipsValue: VipsTextWrap {
        switch self {
        case .word: VIPS_TEXT_WRAP_WORD
        case .character: VIPS_TEXT_WRAP_CHAR
        case .wordCharacter: VIPS_TEXT_WRAP_WORD_CHAR
        case .none: VIPS_TEXT_WRAP_NONE
        }
    }
}

extension TextAlignment {
    fileprivate var vipsValue: VipsAlign {
        switch self {
        case .left: VIPS_ALIGN_LOW
        case .center: VIPS_ALIGN_CENTRE
        case .right: VIPS_ALIGN_HIGH
        }
    }
}

extension NativeImage {
    /// Renders `source` to an RGBA image: glyphs, then stroke, shadow and
    /// rotation as a small fixed graph.
    ///
    /// The graph does not grow with the stroke width: the outline is one
    /// dilation and every layer is blended by a single composite.
    static func renderText(_ source: TextSource, trace: PlanTrace? = nil) throws -> NativeImage {
        try VipsRuntime.ensureInitialized()
        guard swift_vips_operation_exists("text") != 0 else {
            throw HokusaiError.unsupported(feature: "text rendering", reason: "libvips was built without Pango support")
        }
        if let file = source.style.fontFile, !FileManager.default.isReadableFile(atPath: file.path) {
            let exists = FileManager.default.fileExists(atPath: file.path)
            throw HokusaiError.io(url: file, operation: .read, reason: exists ? "file is not readable" : "file not found")
        }

        let glyphs = try renderGlyphs(source)
        let rotated = source.style.rotation.truncatingRemainder(dividingBy: 360) == 0
            ? glyphs
            : try glyphs.rotate(degrees: source.style.rotation, background: [0, 0, 0, 0], interpolation: .bilinear)
        // Glyphs are rendered opaque and the colour's opacity is applied last:
        // Pango reads an alpha of 0 in "#RRGGBBAA" as "not set", and a shadow
        // or outline should follow the glyph shape, not its opacity.
        let opacity = try source.style.color.rgba8()[3] / 255
        guard source.style.stroke != nil || source.style.shadow != nil else { return try rotated.scalingAlpha(by: opacity) }
        return try rotated.decorated(stroke: source.style.stroke, shadow: source.style.shadow, opacity: opacity, trace: trace)
    }

    /// One libvips `text` render in the style's colour.
    private static func renderGlyphs(_ source: TextSource) throws -> NativeImage {
        let style = source.style
        let spacing = style.lineHeight == 1 ? 0 : try lineSpacing(for: source)
        var width = 0, height = 0, dpi = style.dpi
        var wrap = TextWrap.none
        switch source.layout {
        case .natural: break
        case .width(let w, let w2): (width, wrap) = (w, w2)
        case .fit(let w, let h): (width, height, dpi, wrap) = (w, h, 0, .word)
        }
        return try render(
            markup: markup(for: source), source: source,
            width: width, height: height, dpi: dpi, wrap: wrap, spacing: spacing)
    }

    /// The text wrapped in a span that sets the foreground colour.
    private static func markup(for source: TextSource) -> String {
        let body: String
        switch source.content {
        case .plain(let text):
            body = text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        case .markup(let text):
            body = text
        }
        let rgba = (try? source.style.color.rgba8()) ?? [0, 0, 0, 255]
        let hex = String(format: "#%02X%02X%02X", Int(rgba[0].rounded()), Int(rgba[1].rounded()), Int(rgba[2].rounded()))
        return "<span foreground=\"\(hex)\">\(body)</span>"
    }

    private static func render(
        markup: String, source: TextSource, width: Int, height: Int, dpi: Int, wrap: TextWrap, spacing: Int
    ) throws -> NativeImage {
        let style = source.style
        let font = "\(style.font.trimmingCharacters(in: .whitespacesAndNewlines)) \(style.fontSize)"
        let fontFile = style.fontFile?.path
        return try producing({ output in
            markup.withCString { text in
                font.withCString { font in
                    func call(_ file: UnsafePointer<CChar>?) -> Int32 {
                        swift_vips_text_render(
                            output, text, font, file, Int32(width), Int32(height), Int32(dpi),
                            style.alignment.vipsValue, style.justify ? 1 : 0, Int32(spacing), wrap.vipsValue)
                    }
                    if let fontFile { return fontFile.withCString { call($0) } }
                    return call(nil)
                }
            }
        }, failure: {
            if style.fontFile != nil {
                return .invalidInput(reason: "libvips could not render text with the font file; it may be invalid, or this libvips has no fontconfig support")
            }
            if case .markup = source.content {
                return .invalidInput(reason: "the text is not valid Pango markup")
            }
            return .nativeTransform("render text")
        })
    }

    /// Converts the style's line-height multiple into libvips' extra spacing.
    ///
    /// libvips adds `spacing` device pixels between lines, so the multiple
    /// applies to the pitch the font gives at this size, measured by rendering
    /// one and two lines.
    private static func lineSpacing(for source: TextSource) throws -> Int {
        var probe = source
        probe.style.stroke = nil
        probe.style.shadow = nil
        probe.style.lineHeight = 1
        let one = try render(markup: "Ag", source: probe, width: 0, height: 0, dpi: source.style.dpi, wrap: .none, spacing: 0)
        let two = try render(markup: "Ag\nAg", source: probe, width: 0, height: 0, dpi: source.style.dpi, wrap: .none, spacing: 0)
        let pitch = Double(two.height - one.height)
        return Int((pitch * (source.style.lineHeight - 1)).rounded())
    }
}

// MARK: - Stroke and shadow

extension NativeImage {
    /// A copy whose colour bands are `colour` and whose alpha is scaled by its opacity.
    private func recoloured(_ colour: [Double]) throws -> NativeImage {
        let scale = [0, 0, 0, colour[3] / 255]
        let offset = [colour[0], colour[1], colour[2], 0]
        let format = bandFormat
        let linear = try applying("render text") { swift_vips_linear_array($0, $1, scale.map { $0 }, offset, 4) }
        return try linear.castRounded(to: format, operation: "render text")
    }

    /// Pads transparently on every side.
    private func padded(_ amount: Int) throws -> NativeImage {
        guard amount > 0 else { return self }
        return try extend(top: amount, left: amount, bottom: amount, right: amount, mode: .background(.transparent))
    }

    /// Blends an outline and a shadow under this glyph layer in one composite.
    fileprivate func decorated(stroke: TextStroke?, shadow: TextShadow?, opacity: Double, trace: PlanTrace?) throws -> NativeImage {
        let strokeRadius = stroke.map { Int($0.width.rounded(.up)) } ?? 0
        let shadowReach = shadow.map { Int((3 * $0.blur).rounded(.up)) + 1 } ?? 0
        let shadowX = shadow?.offsetX ?? 0, shadowY = shadow?.offsetY ?? 0

        // Everything is placed relative to the glyph layer's own top-left.
        var minX = -strokeRadius, minY = -strokeRadius
        var maxX = width + strokeRadius, maxY = height + strokeRadius
        if shadow != nil {
            minX = min(minX, shadowX - shadowReach)
            minY = min(minY, shadowY - shadowReach)
            maxX = max(maxX, width + shadowX + shadowReach)
            maxY = max(maxY, height + shadowY + shadowReach)
        }

        var layers: [NativeLayer] = []
        func add(_ image: NativeImage, x: Int, y: Int, opacity: Double = 1) {
            layers.append(NativeLayer(image: image, placement: .at(x: x - minX, y: y - minY), blend: .over, opacity: opacity))
        }

        if let shadow {
            let softened = try padded(shadowReach).gaussianBlurIfNeeded(sigma: shadow.blur)
            add(try softened.recoloured(shadow.color.rgba8()), x: shadowX - shadowReach, y: shadowY - shadowReach)
        }
        if let stroke {
            let grown = try padded(strokeRadius).applying("render text") { swift_vips_dilate_round($0, $1, Int32(strokeRadius)) }
            // Dilation is binary; a light blur restores smooth edges.
            let smooth = try grown.gaussianBlurIfNeeded(sigma: 0.6)
            add(try smooth.recoloured(stroke.color.rgba8()), x: -strokeRadius, y: -strokeRadius)
        }
        add(self, x: 0, y: 0, opacity: opacity)

        let clear = try applying("render text") { swift_vips_linear_array($0, $1, [0, 0, 0, 0], [0, 0, 0, 0], 4) }
            .castRounded(to: bandFormat, operation: "render text")
        let canvas = try clear.extend(
            top: -minY, left: -minX, bottom: maxY - height, right: maxX - width, mode: .background(.transparent))
        trace?.record(.compositeBlended(layers: layers.count))
        return try canvas.composite(layers, space: .srgb)
    }

    fileprivate func gaussianBlurIfNeeded(sigma: Double) throws -> NativeImage {
        guard sigma > 0 else { return self }
        return try gaussianBlur(sigma: sigma, precision: .integer, minAmplitude: 0.2)
    }
}
