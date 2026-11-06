import Foundation
import Hokusai

/// A PDF made of vector pages.
///
/// Unlike ``Hokusai/pdf(pageSize:margins:anchor:background:maxEffectiveDPI:metadata:)``, which embeds
/// one finished raster, a document draws text, shapes and gradients as PDF content: text stays
/// selectable and searchable, and shapes stay sharp at any zoom. Images placed on a page are
/// embedded as rasters.
///
/// ```swift
/// let document = VectorDocument(pages: [cover, summary], metadata: PDFDocumentMetadata(title: "Q3 report"))
/// try await document.write(to: URL(fileURLWithPath: "report.pdf"))
/// ```
///
/// Writing draws the pages one at a time: the images of a page are evaluated on Hokusai's scheduler
/// just before it is drawn and released after it, and the drawing and any file output run off Swift's
/// cooperative executor. Cancelling the calling task stops the work with `CancellationError`; a file
/// that was being written is not replaced.
public struct VectorDocument: Sendable {
    public let pages: [VectorPage]
    public let metadata: PDFDocumentMetadata?

    /// A document of `pages`, in order. At least one page is needed to write it.
    public init(pages: [VectorPage], metadata: PDFDocumentMetadata? = nil) {
        self.pages = pages
        self.metadata = metadata
    }

    /// A one-page document.
    public init(_ page: VectorPage, metadata: PDFDocumentMetadata? = nil) {
        self.init(pages: [page], metadata: metadata)
    }

    /// Draws the document and returns the PDF.
    ///
    /// - Throws: ``HokusaiError/invalidInput(reason:)`` for a document without pages,
    ///   ``HokusaiError/transform(_:)`` or the error of an image pipeline that fails,
    ///   ``HokusaiError/invalidOption(name:reason:)`` for invalid text markup, and
    ///   ``HokusaiError/encode(_:)`` when Cairo cannot produce the PDF.
    public func data() async throws -> VectorOutput {
        try await produce(.memory)
    }

    /// Draws the document and writes the PDF to a local file, replacing an existing file atomically.
    ///
    /// The PDF is written to a temporary file in the same directory as Cairo produces it, so a
    /// large document is never held in memory as a whole, and the temporary file replaces the
    /// destination only when the document is complete. A failure or a cancellation leaves an
    /// existing file as it was and removes the temporary file. Parent directories are not created.
    ///
    /// - Throws: As ``data()``, plus ``HokusaiError/io(url:operation:reason:)`` when the file cannot be written.
    @discardableResult
    public func write(to url: URL) async throws -> VectorOutputInfo {
        guard url.isFileURL else {
            throw HokusaiError.invalidOption(name: "url", reason: "write(to:) accepts only file URLs")
        }
        return try await produce(.file(url)).info
    }

    /// Draws the pages one at a time on a serial queue, evaluating each page's images just before
    /// it is drawn and releasing them after, so memory holds the rasters of one page, not of all.
    private func produce(_ destination: VectorRenderer.Session.Destination) async throws -> VectorOutput {
        guard !pages.isEmpty else {
            throw HokusaiError.invalidInput(reason: "a document needs at least one page")
        }
        let cancellation = CancellationFlag()
        let queue = RenderQueue()
        let pages = pages, metadata = metadata
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let first = pages[0].size.dimensions
            let session = try await queue.run {
                try VectorRenderer.Session(firstPage: first, metadata: metadata, destination: destination)
            }
            for page in pages {
                let images = try await Self.evaluateImages(of: page)
                try Task.checkCancellation()
                try await queue.run { try session.draw(page, images: images, cancellation: cancellation) }
            }
            try Task.checkCancellation()
            let output = try await queue.run { try session.finish(cancellation: cancellation) }
            return output
        } onCancel: {
            cancellation.cancel()
        }
    }

    /// Evaluates the images of one page to straight 8-bit RGBA, keyed by item index.
    private static func evaluateImages(of page: VectorPage) async throws -> [Int: RawImage] {
        var images: [Int: RawImage] = [:]
        for (itemIndex, item) in page.items.enumerated() {
            guard case .image(let pipeline, _, _, _) = item else { continue }
            try Task.checkCancellation()
            images[itemIndex] = try await pipeline.raw(.rgba8)
        }
        return images
    }
}

/// A cancellation signal the drawing code can read from a queue, which runs outside the calling
/// task and so cannot ask `Task.isCancelled`.
final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    func check() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw CancellationError() }
    }
}

/// One serial queue for all the work of a document, which Cairo needs: a surface and its context
/// are used by one thread at a time. The calling task suspends while a piece of work runs, so
/// the cooperative executor is never blocked by drawing or by file output.
private struct RenderQueue: Sendable {
    private let queue = DispatchQueue(label: "hokusai.pdf.render", qos: .userInitiated)

    func run<Result: Sendable>(_ work: @escaping @Sendable () throws -> Result) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Swift.Result { try work() })
            }
        }
    }
}
