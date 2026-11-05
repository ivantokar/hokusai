import Foundation
import Hokusai

/// One page of a vector PDF: an ordered list of things to draw.
///
/// A page is an immutable value; every method returns a new page with one more item, drawn on top of
/// the earlier ones. Nothing is rendered until a ``VectorDocument`` is written, and invalid values are
/// rejected here, when the item is added.
///
/// ```swift
/// let page = try VectorPage(size: .a4())
///     .background(.linearGradient(from: navy, to: teal))
///     .image(hero, frame: VectorRect(x: 40, y: 40, width: 515, height: 200), fit: .cover)
///     .text("Quarterly performance", at: VectorPoint(x: 40, y: 270), width: 515,
///           style: VectorTextStyle(family: "sans", size: 28, weight: .bold, color: .white))
/// ```
public struct VectorPage: Sendable {
    enum Item: Sendable {
        case background(VectorPaint)
        case rectangle(VectorRect, fill: VectorPaint?, stroke: VectorStroke?, cornerRadius: Double)
        case line(VectorPoint, VectorPoint, VectorStroke)
        case image(Hokusai, VectorRect, VectorImageFit, opacity: Double)
        case text(TextContent, VectorPoint, width: Double?, VectorTextStyle)
    }

    /// The page size.
    public let size: VectorPageSize
    let items: [Item]

    /// An empty page.
    ///
    /// - Throws: ``HokusaiError/invalidOption(name:reason:)`` for a custom size outside `1...14400` points.
    public init(size: VectorPageSize = .a4()) throws {
        try size.validate()
        self.size = size
        self.items = []
    }

    private init(size: VectorPageSize, items: [Item]) {
        self.size = size
        self.items = items
    }

    private func adding(_ item: Item) -> VectorPage {
        VectorPage(size: size, items: items + [item])
    }

    /// Fills the whole page.
    public func background(_ paint: VectorPaint) throws -> VectorPage {
        try paint.validate()
        return adding(.background(paint))
    }

    /// Draws a rectangle with an optional fill, outline and corner radius.
    ///
    /// - Throws: ``HokusaiError/invalidOption(name:reason:)`` for a frame without area, a
    ///   negative or non-finite radius, or when neither a fill nor a stroke is given.
    public func rectangle(_ frame: VectorRect, fill: VectorPaint? = nil, stroke: VectorStroke? = nil, cornerRadius: Double = 0) throws -> VectorPage {
        try frame.validate("rectangle")
        guard fill != nil || stroke != nil else {
            throw HokusaiError.invalidOption(name: "rectangle", reason: "give a fill, a stroke, or both")
        }
        guard cornerRadius.isFinite, cornerRadius >= 0 else {
            throw HokusaiError.invalidOption(name: "cornerRadius", reason: "must be a finite value of zero or more")
        }
        try fill?.validate()
        try stroke?.validate()
        return adding(.rectangle(frame, fill: fill, stroke: stroke, cornerRadius: cornerRadius))
    }

    /// Draws a straight line.
    public func line(from start: VectorPoint, to end: VectorPoint, stroke: VectorStroke) throws -> VectorPage {
        guard [start.x, start.y, end.x, end.y].allSatisfy(\.isFinite) else {
            throw HokusaiError.invalidOption(name: "line", reason: "coordinates must be finite")
        }
        try stroke.validate()
        return adding(.line(start, end, stroke))
    }

    /// Places a raster image, the result of a Hokusai pipeline, inside `frame`.
    ///
    /// The pipeline is evaluated when the document is written and embedded as a raster, at its own
    /// resolution: resize it to about the pixel size the frame needs (a 515-point frame is 715
    /// pixels wide at 100 dpi) to keep the file small. Its alpha channel is kept.
    ///
    /// - Parameter opacity: `0...1`, multiplied with the image's own alpha.
    public func image(_ image: Hokusai, frame: VectorRect, fit: VectorImageFit = .contain, opacity: Double = 1) throws -> VectorPage {
        try frame.validate("image frame")
        guard opacity.isFinite, (0...1).contains(opacity) else {
            throw HokusaiError.invalidOption(name: "opacity", reason: "must be a finite value from 0 through 1")
        }
        return adding(.image(image, frame, fit, opacity: opacity))
    }

    /// Draws text, laid out by Pango and written to the PDF as selectable, searchable text.
    ///
    /// - Parameters:
    ///   - content: Plain text (any characters are safe) or Pango markup for mixed fonts and
    ///     colours inside one block. Invalid markup is reported when the document is written.
    ///   - origin: The top-left corner of the text block.
    ///   - width: The width to wrap lines to, in points. `nil` does not wrap; only line breaks in
    ///     the text start a new line.
    ///   - style: The typography.
    public func text(_ content: TextContent, at origin: VectorPoint, width: Double? = nil, style: VectorTextStyle = VectorTextStyle()) throws -> VectorPage {
        guard origin.x.isFinite, origin.y.isFinite else {
            throw HokusaiError.invalidOption(name: "text origin", reason: "coordinates must be finite")
        }
        if let width {
            guard width.isFinite, width > 0 else {
                throw HokusaiError.invalidOption(name: "text width", reason: "must be a finite value greater than zero")
            }
        }
        switch content {
        case .plain(let text), .markup(let text):
            guard !text.isEmpty, !text.contains("\0") else {
                throw HokusaiError.invalidOption(name: "text", reason: "must be non-empty and contain no NUL character")
            }
        }
        try style.validate()
        return adding(.text(content, origin, width: width, style))
    }
}
