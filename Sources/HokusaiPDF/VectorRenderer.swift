import Foundation
import Hokusai
import CPangoCairo

/// Draws pages with Cairo and Pango into a PDF.
///
/// The drawing is synchronous. ``Session`` draws one page at a time, so the caller can evaluate the
/// images of a page just before drawing it and let them go afterwards. A session is not thread
/// safe: ``VectorDocument`` runs every call on one serial queue.
enum VectorRenderer {
    /// A PDF being drawn, page by page, into memory or into a file.
    final class Session: @unchecked Sendable {
        /// Where the PDF goes. A file is written as Cairo produces it, through a temporary file in
        /// the destination's directory that replaces the destination when the document is finished.
        enum Destination {
            case memory
            case file(URL)
        }

        private let buffer = UnsafeMutablePointer<HokusaiPDFBuffer>.allocate(capacity: 1)
        private var surface: OpaquePointer?
        private var context: OpaquePointer?
        private let destination: Destination
        private var temporary: URL?
        private var pagesDrawn = 0
        private var released = false

        init(firstPage: (width: Double, height: Double), metadata: PDFDocumentMetadata?, destination: Destination) throws {
            buffer.initialize(to: HokusaiPDFBuffer())
            self.destination = destination
            do {
                guard hokusai_vector_pdf_available() != 0 else {
                    throw HokusaiError.unsupported(feature: "vector PDF", reason: "this Cairo build has no PDF surface")
                }
                if case .file(let url) = destination { try openTemporary(beside: url) }
                guard let surface = hokusai_pdf_surface_create(buffer, firstPage.width, firstPage.height) else {
                    throw VectorRenderer.encodeFailure("could not create the PDF surface")
                }
                self.surface = surface
                try VectorRenderer.check(surface: surface, "create the PDF surface")
                if let metadata { VectorRenderer.apply(metadata, to: surface) }
                guard let cr = cairo_create(surface) else {
                    throw VectorRenderer.encodeFailure("could not create a drawing context")
                }
                context = cr
            } catch {
                release()
                throw error
            }
        }

        deinit { release() }

        /// Draws one page. `images` holds the evaluated image of each image item, by item index.
        func draw(_ page: VectorPage, images: [Int: RawImage], cancellation: CancellationFlag) throws {
            guard let surface, let cr = context else { throw VectorRenderer.encodeFailure("the document is already finished") }
            let pageNumber = pagesDrawn + 1
            let size = page.size.dimensions
            do {
                cairo_pdf_surface_set_size(surface, size.width, size.height)
                for (itemIndex, item) in page.items.enumerated() {
                    try cancellation.check()
                    try VectorRenderer.draw(item, on: cr, pageSize: size, image: images[itemIndex])
                    try VectorRenderer.check(context: cr, "draw page \(pageNumber)")
                }
                cairo_show_page(cr)
                try VectorRenderer.check(context: cr, "finish page \(pageNumber)")
            } catch {
                throw translated(error)
            }
            pagesDrawn += 1
        }

        /// Finishes the PDF. For a file destination the data is empty: the file is complete and has
        /// replaced the destination.
        func finish(cancellation: CancellationFlag) throws -> VectorOutput {
            guard let surface else { throw VectorRenderer.encodeFailure("the document is already finished") }
            do {
                cairo_surface_finish(surface)
                try VectorRenderer.check(surface: surface, "write the PDF")
                if buffer.pointee.failed != 0 { throw VectorRenderer.encodeFailure("could not collect the PDF bytes") }
            } catch {
                throw translated(error)
            }
            let byteCount = buffer.pointee.length
            let info = VectorOutputInfo(pageCount: pagesDrawn, byteCount: byteCount)
            switch destination {
            case .memory:
                guard let bytes = buffer.pointee.data else { throw VectorRenderer.encodeFailure("could not collect the PDF bytes") }
                return VectorOutput(data: Data(bytes: bytes, count: byteCount), info: info)
            case .file(let url):
                try cancellation.check()
                try commitTemporary(to: url)
                return VectorOutput(data: Data(), info: info)
            }
        }

        // MARK: File output

        private func openTemporary(beside url: URL) throws {
            let name = ".\(url.lastPathComponent).hokusai-\(UUID().uuidString)"
            let path = url.deletingLastPathComponent().appendingPathComponent(name)
            // Created with the usual 0666 modified by the umask, like a file a plain write creates.
            let descriptor = open(path.path, O_WRONLY | O_CREAT | O_EXCL, 0o666)
            guard descriptor >= 0 else {
                throw HokusaiError.io(url: url, operation: .write, reason: "could not create a temporary file: \(String(cString: strerror(errno)))")
            }
            temporary = path
            hokusai_pdf_buffer_use_file(buffer, descriptor)
        }

        private func commitTemporary(to url: URL) throws {
            guard let temporary else { return }
            let descriptor = buffer.pointee.fd
            buffer.pointee.fd = -1
            let synced = fsync(descriptor) == 0
            let syncError = errno
            let closed = close(descriptor) == 0
            let closeError = errno
            guard synced, closed else {
                throw HokusaiError.io(url: url, operation: .write, reason: String(cString: strerror(synced ? closeError : syncError)))
            }
            guard rename(temporary.path, url.path) == 0 else {
                throw HokusaiError.io(url: url, operation: .write, reason: "could not replace the file: \(String(cString: strerror(errno)))")
            }
            self.temporary = nil
        }

        /// A failed write to the file is an I/O error of that file, not a Cairo failure.
        private func translated(_ error: Error) -> Error {
            guard case .file(let url) = destination, buffer.pointee.failed != 0, buffer.pointee.error != 0 else { return error }
            return HokusaiError.io(url: url, operation: .write, reason: String(cString: strerror(buffer.pointee.error)))
        }

        private func release() {
            guard !released else { return }
            released = true
            if let context { cairo_destroy(context) }
            if let surface { cairo_surface_destroy(surface) }
            context = nil
            surface = nil
            if buffer.pointee.to_file != 0, buffer.pointee.fd >= 0 { close(buffer.pointee.fd) }
            // A temporary that was never committed is an unfinished or cancelled document.
            if let temporary { unlink(temporary.path) }
            temporary = nil
            hokusai_pdf_buffer_free(buffer)
            buffer.deallocate()
        }
    }

    // MARK: - Items

    private static func draw(_ item: VectorPage.Item, on cr: OpaquePointer, pageSize: (width: Double, height: Double), image: RawImage?) throws {
        switch item {
        case .background(let paint):
            let area = VectorRect(x: 0, y: 0, width: pageSize.width, height: pageSize.height)
            cairo_save(cr)
            try setSource(paint, over: area, on: cr)
            cairo_paint(cr)
            cairo_restore(cr)

        case .rectangle(let frame, let fill, let stroke, let radius):
            cairo_save(cr)
            if let fill {
                path(frame, radius: radius, on: cr)
                try setSource(fill, over: frame, on: cr)
                cairo_fill(cr)
            }
            if let stroke {
                path(frame, radius: radius, on: cr)
                setColor(stroke.color, on: cr)
                cairo_set_line_width(cr, stroke.width)
                cairo_stroke(cr)
            }
            cairo_restore(cr)

        case .line(let start, let end, let stroke):
            cairo_save(cr)
            cairo_move_to(cr, start.x, start.y)
            cairo_line_to(cr, end.x, end.y)
            setColor(stroke.color, on: cr)
            cairo_set_line_width(cr, stroke.width)
            cairo_stroke(cr)
            cairo_restore(cr)

        case .image(_, let frame, let fit, let opacity):
            guard let image else { throw VectorRenderer.encodeFailure("an image was not evaluated") }
            try drawImage(image, in: frame, fit: fit, opacity: opacity, on: cr)

        case .text(let content, let origin, let width, let style):
            try drawText(content, at: origin, width: width, style: style, on: cr)
        }
    }

    private static func path(_ frame: VectorRect, radius: Double, on cr: OpaquePointer) {
        let r = min(radius, frame.width / 2, frame.height / 2)
        cairo_new_path(cr)
        if r <= 0 {
            cairo_rectangle(cr, frame.x, frame.y, frame.width, frame.height)
            return
        }
        let (x, y, w, h) = (frame.x, frame.y, frame.width, frame.height)
        cairo_arc(cr, x + w - r, y + r, r, -.pi / 2, 0)
        cairo_arc(cr, x + w - r, y + h - r, r, 0, .pi / 2)
        cairo_arc(cr, x + r, y + h - r, r, .pi / 2, .pi)
        cairo_arc(cr, x + r, y + r, r, .pi, 3 * .pi / 2)
        cairo_close_path(cr)
    }

    private static func setColor(_ color: Color, on cr: OpaquePointer) {
        cairo_set_source_rgba(cr, color.red, color.green, color.blue, color.opacity)
    }

    private static func setSource(_ paint: VectorPaint, over area: VectorRect, on cr: OpaquePointer) throws {
        switch paint {
        case .color(let color):
            setColor(color, on: cr)
        case .linearGradient(let stops, let angle):
            // The gradient line passes through the centre and is as long as the area projects onto it,
            // so the first stop touches one corner and the last the opposite one.
            let radians = angle * .pi / 180
            let (dx, dy) = (cos(radians), sin(radians))
            let half = (abs(area.width * dx) + abs(area.height * dy)) / 2
            let (cx, cy) = (area.x + area.width / 2, area.y + area.height / 2)
            guard let pattern = cairo_pattern_create_linear(cx - dx * half, cy - dy * half, cx + dx * half, cy + dy * half) else {
                throw VectorRenderer.encodeFailure("could not create a gradient")
            }
            defer { cairo_pattern_destroy(pattern) }
            for stop in stops {
                cairo_pattern_add_color_stop_rgba(pattern, stop.offset, stop.color.red, stop.color.green, stop.color.blue, stop.color.opacity)
            }
            cairo_set_source(cr, pattern)
        }
    }

    private static func drawImage(_ raw: RawImage, in frame: VectorRect, fit: VectorImageFit, opacity: Double, on cr: OpaquePointer) throws {
        let width = Int32(raw.width), height = Int32(raw.height)
        let stride = cairo_format_stride_for_width(CAIRO_FORMAT_ARGB32, width)
        guard stride > 0 else { throw VectorRenderer.encodeFailure("an image is too wide") }
        var pixels = [UInt8](repeating: 0, count: Int(stride) * Int(height))
        raw.data.withUnsafeBytes { source in
            pixels.withUnsafeMutableBufferPointer { destination in
                hokusai_rgba_to_cairo(
                    source.bindMemory(to: UInt8.self).baseAddress, destination.baseAddress, width, height, stride)
            }
        }
        try pixels.withUnsafeMutableBufferPointer { buffer in
            guard let surface = cairo_image_surface_create_for_data(buffer.baseAddress, CAIRO_FORMAT_ARGB32, width, height, stride) else {
                throw VectorRenderer.encodeFailure("could not wrap an image")
            }
            defer { cairo_surface_destroy(surface) }
            try check(surface: surface, "wrap an image")

            let (iw, ih) = (Double(width), Double(height))
            let scaleX: Double, scaleY: Double
            switch fit {
            case .fill: (scaleX, scaleY) = (frame.width / iw, frame.height / ih)
            case .contain: let s = min(frame.width / iw, frame.height / ih); (scaleX, scaleY) = (s, s)
            case .cover: let s = max(frame.width / iw, frame.height / ih); (scaleX, scaleY) = (s, s)
            }
            let (drawWidth, drawHeight) = (iw * scaleX, ih * scaleY)

            cairo_save(cr)
            cairo_rectangle(cr, frame.x, frame.y, frame.width, frame.height)
            cairo_clip(cr)
            cairo_translate(cr, frame.x + (frame.width - drawWidth) / 2, frame.y + (frame.height - drawHeight) / 2)
            cairo_scale(cr, scaleX, scaleY)
            cairo_set_source_surface(cr, surface, 0, 0)
            if let pattern = cairo_get_source(cr) {
                cairo_pattern_set_filter(pattern, CAIRO_FILTER_BEST)
                // Cover and fill reach past the frame, so the edge pixels are repeated to avoid a seam
                // from filtering; contain must leave the rest of the frame empty.
                if fit != .contain { cairo_pattern_set_extend(pattern, CAIRO_EXTEND_PAD) }
            }
            cairo_paint_with_alpha(cr, opacity)
            cairo_restore(cr)
            // Cairo reads the pixels while it paints; the PDF surface copies them into the document
            // at that point, but a flush keeps the buffer valid for the whole call regardless.
            cairo_surface_flush(surface)
        }
    }

    private static func drawText(_ content: TextContent, at origin: VectorPoint, width: Double?, style: VectorTextStyle, on cr: OpaquePointer) throws {
        let (text, markup): (String, Bool)
        switch content {
        case .plain(let value): (text, markup) = (value, false)
        case .markup(let value): (text, markup) = (value, true)
        }
        var height = 0.0
        let status = hokusai_draw_text(
            cr, text, markup ? 1 : 0, origin.x, origin.y, width ?? -1, style.family, style.size, Int32(style.weight.rawValue),
            style.italic ? 1 : 0, style.color.red, style.color.green, style.color.blue, style.color.opacity,
            Int32(style.alignment.rawValue), Int32(style.wrap.rawValue), style.lineSpacing, &height)
        guard status == 0 else {
            throw HokusaiError.invalidOption(name: "text", reason: "the Pango markup is not valid")
        }
    }

    // MARK: - Metadata and status

    private static func apply(_ metadata: PDFDocumentMetadata, to surface: OpaquePointer) {
        if let value = metadata.title { hokusai_pdf_set_metadata(surface, Int32(CAIRO_PDF_METADATA_TITLE.rawValue), value) }
        if let value = metadata.author { hokusai_pdf_set_metadata(surface, Int32(CAIRO_PDF_METADATA_AUTHOR.rawValue), value) }
        if let value = metadata.subject { hokusai_pdf_set_metadata(surface, Int32(CAIRO_PDF_METADATA_SUBJECT.rawValue), value) }
        if let value = metadata.keywords { hokusai_pdf_set_metadata(surface, Int32(CAIRO_PDF_METADATA_KEYWORDS.rawValue), value) }
        if let value = metadata.creator { hokusai_pdf_set_metadata(surface, Int32(CAIRO_PDF_METADATA_CREATOR.rawValue), value) }
        let formatter = ISO8601DateFormatter()
        if let date = metadata.creationDate {
            hokusai_pdf_set_metadata(surface, Int32(CAIRO_PDF_METADATA_CREATE_DATE.rawValue), formatter.string(from: date))
        }
        if let date = metadata.modificationDate {
            hokusai_pdf_set_metadata(surface, Int32(CAIRO_PDF_METADATA_MOD_DATE.rawValue), formatter.string(from: date))
        }
    }

    private static func check(context cr: OpaquePointer, _ operation: String) throws {
        let status = cairo_status(cr)
        guard status == CAIRO_STATUS_SUCCESS else {
            throw VectorRenderer.encodeFailure("could not \(operation): \(String(cString: cairo_status_to_string(status)))")
        }
    }

    private static func check(surface: OpaquePointer, _ operation: String) throws {
        let status = cairo_surface_status(surface)
        guard status == CAIRO_STATUS_SUCCESS else {
            throw VectorRenderer.encodeFailure("could not \(operation): \(String(cString: cairo_status_to_string(status)))")
        }
    }

    fileprivate static func encodeFailure(_ reason: String) -> HokusaiError {
        .encode(FailureContext(operation: "encode vector pdf", reason: reason))
    }
}

private extension Int32 {
    var boolValue: Bool { self != 0 }
}
