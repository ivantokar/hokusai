import Foundation
import CVips
import CCairo

// MARK: - Page layout

/// A resolved page: its size and where the aspect-fitted raster sits, in points.
struct PDFPageLayout: Equatable {
    var pageWidth: Double
    var pageHeight: Double
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    /// The raster's resolution on the page, in dots per inch.
    func effectiveDPI(pixelWidth: Int) -> Double {
        Double(pixelWidth) / (width / 72)
    }
}

enum PDFLayout {
    /// ISO A4 in points.
    static let a4 = (width: 595.276, height: 841.890)
    /// US Letter in points.
    static let letter = (width: 612.0, height: 792.0)

    /// Rejects option values that cannot describe a page, before any work starts.
    static func validate(_ options: PDFOptions) throws {
        func positive(_ value: Double, _ name: String) throws {
            guard value.isFinite, value > 0 else {
                throw HokusaiError.invalidOption(name: name, reason: "must be a finite value greater than zero")
            }
        }
        switch options.pageSize {
        case .image(let dpi): try positive(dpi, "pageSize.dpi")
        case .points(let width, let height):
            try positive(width, "pageSize.width")
            try positive(height, "pageSize.height")
        case .a4, .letter: break
        }
        for (value, name) in [
            (options.margins.top, "margins.top"), (options.margins.leading, "margins.leading"),
            (options.margins.bottom, "margins.bottom"), (options.margins.trailing, "margins.trailing"),
        ] where !value.isFinite || value < 0 {
            throw HokusaiError.invalidOption(name: name, reason: "must be a finite value of zero or more")
        }
        if let background = options.background { _ = try background.rgba8() }
        if let maximum = options.maxEffectiveDPI { try positive(maximum, "maxEffectiveDPI") }
    }

    /// Places a raster of the given pixel size on the page the options describe.
    ///
    /// The raster is scaled uniformly to fit the page inside its margins and
    /// positioned by `anchor`. An `.image(dpi:)` page is the raster at that
    /// resolution plus the margins, so the raster fills it exactly.
    static func resolve(pixelWidth: Int, pixelHeight: Int, options: PDFOptions) throws -> PDFPageLayout {
        let margins = options.margins
        let horizontal = margins.leading + margins.trailing
        let vertical = margins.top + margins.bottom
        let pixels = (width: Double(pixelWidth), height: Double(pixelHeight))

        let page: (width: Double, height: Double)
        switch options.pageSize {
        case .image(let dpi):
            page = (pixels.width / dpi * 72 + horizontal, pixels.height / dpi * 72 + vertical)
        case .a4(let orientation):
            page = orientation == .portrait ? a4 : (a4.height, a4.width)
        case .letter(let orientation):
            page = orientation == .portrait ? letter : (letter.height, letter.width)
        case .points(let width, let height):
            page = (width, height)
        }

        let box = (width: page.width - horizontal, height: page.height - vertical)
        guard box.width > 0, box.height > 0 else {
            throw HokusaiError.invalidOption(name: "margins", reason: "leave no room for the image on the page")
        }

        let scale = min(box.width / pixels.width, box.height / pixels.height)
        let placed = (width: pixels.width * scale, height: pixels.height * scale)
        let free = (width: box.width - placed.width, height: box.height - placed.height)

        let fractionX: Double, fractionY: Double
        switch options.anchor {
        case .northWest, .west, .southWest: fractionX = 0
        case .north, .center, .south: fractionX = 0.5
        case .northEast, .east, .southEast: fractionX = 1
        }
        switch options.anchor {
        case .northWest, .north, .northEast: fractionY = 0
        case .west, .center, .east: fractionY = 0.5
        case .southWest, .south, .southEast: fractionY = 1
        }

        return PDFPageLayout(
            pageWidth: page.width, pageHeight: page.height,
            x: margins.leading + free.width * fractionX,
            y: margins.top + free.height * fractionY,
            width: placed.width, height: placed.height
        )
    }
}

// MARK: - Output sink

/// Receives the PDF bytes Cairo produces.
///
/// One class serves both destinations, so memory and file output share a single
/// write path. A file is created by the first write, so a pipeline that fails
/// before producing output never touches the destination; a write that fails
/// after output began removes the regular file being written rather than
/// leaving a partial document. File failures are recorded from the system
/// error code and surface as ``HokusaiError/io(url:operation:reason:)``.
final class PDFOutputSink {
    enum Destination {
        case memory
        case file(URL)
    }

    let destination: Destination
    private let isCancelled: () -> Bool

    /// Bytes accepted so far.
    private(set) var byteCount = 0

    /// The first system error from the destination, or 0.
    private(set) var errorCode: Int32 = 0

    // Memory destination: one growing buffer, transferred to `Data` without a copy.
    private var buffer: UnsafeMutablePointer<UInt8>?
    private var capacity = 0

    // File destination.
    private var descriptor: Int32 = -1
    private var isRegularFile = false

    init(destination: Destination, isCancelled: @escaping () -> Bool = { false }) {
        self.destination = destination
        self.isCancelled = isCancelled
    }

    deinit {
        if descriptor >= 0 { close(descriptor) }
        if let buffer { free(buffer) }
    }

    /// Accepts `count` bytes. Returns false to make Cairo abort the document.
    func write(_ bytes: UnsafePointer<UInt8>, count: Int) -> Bool {
        guard errorCode == 0, !isCancelled() else { return false }
        switch destination {
        case .memory: return append(bytes, count: count)
        case .file(let url): return writeToFile(bytes, count: count, url: url)
        }
    }

    private func append(_ bytes: UnsafePointer<UInt8>, count: Int) -> Bool {
        let (needed, overflow) = byteCount.addingReportingOverflow(count)
        guard !overflow else { errorCode = ENOMEM; return false }
        if needed > capacity {
            var grown = max(capacity, 64 * 1024)
            while grown < needed {
                let (doubled, wrapped) = grown.multipliedReportingOverflow(by: 2)
                guard !wrapped else { errorCode = ENOMEM; return false }
                grown = doubled
            }
            guard let resized = realloc(buffer, grown) else { errorCode = ENOMEM; return false }
            buffer = resized.assumingMemoryBound(to: UInt8.self)
            capacity = grown
        }
        memcpy(buffer! + byteCount, bytes, count)
        byteCount = needed
        return true
    }

    private func writeToFile(_ bytes: UnsafePointer<UInt8>, count: Int, url: URL) -> Bool {
        if descriptor < 0 {
            descriptor = open(url.path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0o666)
            guard descriptor >= 0 else { errorCode = errno; return false }
            var info = stat()
            isRegularFile = fstat(descriptor, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
        }
        var offset = 0
        while offset < count {
            let written = systemWrite(descriptor, bytes + offset, count - offset)
            if written < 0 {
                if errno == EINTR { continue }
                errorCode = errno
                return false
            }
            offset += written
            byteCount += written
        }
        return true
    }

    /// Finishes the destination and returns the I/O failure, if any.
    ///
    /// On success a file is closed (a failing close is reported). On failure a
    /// regular file that was being written is closed and removed; devices and
    /// pipes are only closed.
    func complete(success: Bool) -> HokusaiError? {
        if case .file(let url) = destination, descriptor >= 0 {
            if close(descriptor) != 0, errorCode == 0 { errorCode = errno }
            descriptor = -1
            if (!success || errorCode != 0), isRegularFile { unlink(url.path) }
        }
        return ioError
    }

    /// The destination failure as a typed error, when there was one.
    var ioError: HokusaiError? {
        guard errorCode != 0, case .file(let url) = destination else { return nil }
        return .io(url: url, operation: .write, reason: String(cString: strerror(errorCode)))
    }

    /// Hands the collected bytes to `Data` without copying them.
    func takeData() -> Data {
        guard let buffer else { return Data() }
        self.buffer = nil
        let count = byteCount
        capacity = 0
        return Data(bytesNoCopy: buffer, count: count, deallocator: .free)
    }
}

/// The POSIX `write(2)`, named so it is not confused with ``PDFOutputSink/write(_:count:)``.
private func systemWrite(_ descriptor: Int32, _ bytes: UnsafePointer<UInt8>, _ count: Int) -> Int {
    #if canImport(Darwin)
    return Darwin.write(descriptor, bytes, count)
    #else
    return Glibc.write(descriptor, bytes, count)
    #endif
}

/// Cairo's write callback: forwards bytes to the ``PDFOutputSink`` in `context`.
private let pdfSinkWrite: HokusaiPDFWrite = { context, data, length in
    guard let context, let data else { return 1 }
    let sink = Unmanaged<PDFOutputSink>.fromOpaque(context).takeUnretainedValue()
    return sink.write(data, count: Int(length)) ? 0 : 1
}

// MARK: - Page raster

/// A page image in the exact form Cairo draws: premultiplied native-endian
/// ARGB32 held in one buffer.
final class CairoRaster {
    let pixels: UnsafeMutableRawPointer
    let width: Int
    let height: Int
    let stride: Int

    fileprivate init(pixels: UnsafeMutableRawPointer, width: Int, height: Int, stride: Int) {
        self.pixels = pixels
        self.width = width
        self.height = height
        self.stride = stride
    }

    deinit { g_free(pixels) }
}

extension NativeImage {
    /// Converts this image to a ``CairoRaster``, materialising exactly one
    /// full-size buffer.
    ///
    /// libvips brings the image to 8-bit sRGB with alpha and writes it once;
    /// the same buffer is then premultiplied and reordered in place into
    /// Cairo's native layout. No second raster is allocated. It is not colour
    /// managed: an embedded ICC profile is neither applied nor embedded in the
    /// PDF.
    func cairoRaster() throws -> CairoRaster {
        func step(_ source: NativeImage, _ body: (NativeImage.Pointer, UnsafeMutablePointer<NativeImage.Pointer?>) -> Int32) throws -> NativeImage {
            try NativeImage.producing({ body(source.pointer, $0) }, failure: { .nativeEncode("pdf") })
        }

        let eightBit = try step(try step(self) { swift_vips_colourspace_srgb($0, $1) }) { swift_vips_cast_uchar($0, $1) }
        guard eightBit.bands == 3 || eightBit.bands == 4 else {
            throw HokusaiError.encode(FailureContext(
                operation: "encode pdf", reason: "PDF output needs an RGB or RGBA image, found \(eightBit.bands) bands"))
        }
        let rgba = eightBit.bands == 4 ? eightBit : try step(eightBit) { swift_vips_addalpha($0, $1) }

        let width = rgba.width, height = rgba.height
        let stride = Int(hokusai_cairo_argb32_stride(Int32(width)))
        let (rowBytes, rowOverflow) = width.multipliedReportingOverflow(by: 4)
        let (total, totalOverflow) = stride.multipliedReportingOverflow(by: height)
        guard stride > 0, !rowOverflow, !totalOverflow, stride == rowBytes else {
            throw HokusaiError.encode(FailureContext(
                operation: "encode pdf", reason: "a \(width)×\(height) raster does not fit Cairo's pixel layout"))
        }

        var size = 0
        guard let memory = vips_image_write_to_memory(rgba.pointer, &size) else {
            throw HokusaiError.nativeEncode("pdf")
        }
        guard size == total else {
            g_free(memory)
            throw HokusaiError.encode(FailureContext(
                operation: "encode pdf", reason: "the page raster has an unexpected size"))
        }
        hokusai_rgba_to_argb32_premultiplied(memory.assumingMemoryBound(to: UInt8.self), width * height)
        return CairoRaster(pixels: memory, width: width, height: height, stride: stride)
    }
}

// MARK: - Document writer

/// Writes a PDF one page at a time into a ``PDFOutputSink``.
///
/// The writer can emit any number of pages, each with its own size; today the
/// terminal writes one. It is a thin owner of the Cairo document, not a layout
/// engine.
final class PDFDocumentWriter {
    private let sink: PDFOutputSink
    private var document: UnsafeMutablePointer<HokusaiPDF>?

    /// Begins a document whose first page is `firstPage` points.
    init(sink: PDFOutputSink, firstPage: (width: Double, height: Double), metadata: PDFDocumentMetadata?) throws {
        self.sink = sink
        func copy(_ text: String?) -> UnsafeMutablePointer<CChar>? { text.flatMap { strdup($0) } }
        let title = copy(metadata?.title), author = copy(metadata?.author), subject = copy(metadata?.subject)
        let keywords = copy(metadata?.keywords), creator = copy(metadata?.creator)
        // Cairo wants ISO 8601 in UTC, for example 2026-10-14T12:30:00Z.
        func iso(_ date: Date?) -> String? {
            date.map { Date.ISO8601FormatStyle(timeZone: .gmt).format($0) }
        }
        let created = copy(iso(metadata?.creationDate)), modified = copy(iso(metadata?.modificationDate))
        let allocations: [UnsafeMutablePointer<CChar>?] = [title, author, subject, keywords, creator, created, modified]
        defer { for pointer in allocations { free(pointer) } }

        document = hokusai_pdf_begin(
            pdfSinkWrite, Unmanaged.passUnretained(sink).toOpaque(),
            firstPage.width, firstPage.height, title, author, subject, keywords, creator, created, modified)
        guard document != nil else {
            throw HokusaiError.runtime(FailureContext(operation: "encode pdf", reason: "could not allocate a PDF document"))
        }
    }

    deinit {
        if let document { hokusai_pdf_free(document) }
    }

    /// Draws one page: the optional background, then `raster` at `layout`.
    func addPage(_ raster: CairoRaster, layout: PDFPageLayout, background: Color?) throws {
        let rgba = try background?.rgba8().map { $0 / 255 } ?? [0, 0, 0, 0]
        let status = hokusai_pdf_add_page(
            document, layout.pageWidth, layout.pageHeight,
            background == nil ? 0 : 1, rgba[0], rgba[1], rgba[2], rgba[3],
            raster.pixels.assumingMemoryBound(to: UInt8.self), Int32(raster.width), Int32(raster.height), Int32(raster.stride),
            layout.x, layout.y, layout.width, layout.height)
        try check(status)
    }

    /// Finishes the document and returns its page count.
    func finish() throws -> Int {
        try check(hokusai_pdf_finish(document))
        return Int(hokusai_pdf_page_count(document))
    }

    /// Maps a Cairo status to a typed error: the sink's I/O failure when the
    /// destination refused bytes, otherwise an encode failure carrying Cairo's
    /// own description (never libvips' error log).
    private func check(_ status: Int32) throws {
        guard status != 0 else { return }
        if let ioError = sink.ioError { throw ioError }
        throw HokusaiError.encode(FailureContext(
            operation: "encode pdf",
            reason: "Cairo could not write the PDF document",
            diagnostic: String(cString: hokusai_cairo_status_string(status))))
    }
}

// MARK: - Terminal

/// What a PDF write produced.
struct PDFRenderResult {
    let details: PDFOutputDetails
    let rasterWidth: Int
    let rasterHeight: Int
}

extension NativeImage {
    /// Renders this image as a PDF into `sink` and completes the sink.
    ///
    /// When `maxEffectiveDPI` is set and the raster would exceed it on the
    /// page, the image is first downsampled with a normal libvips resize.
    func writePDF(_ options: PDFOptions, into sink: PDFOutputSink) throws -> PDFRenderResult {
        do {
            var image = self
            var layout = try PDFLayout.resolve(pixelWidth: width, pixelHeight: height, options: options)

            if let maximum = options.maxEffectiveDPI, layout.effectiveDPI(pixelWidth: width) > maximum {
                let targetWidth = max(1, Int((layout.width / 72 * maximum).rounded(.up)))
                let targetHeight = max(1, Int((Double(targetWidth) * Double(height) / Double(width)).rounded()))
                image = try self.resize(
                    width: targetWidth, height: targetHeight, fit: .fill, position: .center, kernel: .lanczos3,
                    withoutEnlargement: false, withoutReduction: false, background: [0, 0, 0, 255])
                layout = try PDFLayout.resolve(pixelWidth: image.width, pixelHeight: image.height, options: options)
            }

            let raster = try image.cairoRaster()
            let writer = try PDFDocumentWriter(
                sink: sink, firstPage: (layout.pageWidth, layout.pageHeight), metadata: options.metadata)
            try writer.addPage(raster, layout: layout, background: options.background)
            let pages = try writer.finish()

            if let ioError = sink.complete(success: true) { throw ioError }
            return PDFRenderResult(
                details: PDFOutputDetails(pageCount: pages, pageWidth: layout.pageWidth, pageHeight: layout.pageHeight),
                rasterWidth: raster.width, rasterHeight: raster.height)
        } catch {
            _ = sink.complete(success: false)
            throw error
        }
    }
}
