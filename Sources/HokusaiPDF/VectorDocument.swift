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
/// Writing evaluates every image pipeline on Hokusai's scheduler, then draws the pages and encodes
/// the PDF off Swift's cooperative executor. Cancelling the calling task stops the work with
/// `CancellationError`.
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
        guard !pages.isEmpty else {
            throw HokusaiError.invalidInput(reason: "a document needs at least one page")
        }
        let images = try await evaluateImages()
        try Task.checkCancellation()
        let pages = pages, metadata = metadata
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try VectorRenderer.render(pages: pages, images: images, metadata: metadata) })
            }
        }
    }

    /// Draws the document and writes the PDF to a local file, replacing an existing file atomically.
    ///
    /// The file is written through a temporary file in the same directory, so a failure leaves an
    /// existing file as it was. Parent directories are not created.
    ///
    /// - Throws: As ``data()``, plus ``HokusaiError/io(url:operation:reason:)`` when the file cannot be written.
    @discardableResult
    public func write(to url: URL) async throws -> VectorOutputInfo {
        guard url.isFileURL else {
            throw HokusaiError.invalidOption(name: "url", reason: "write(to:) accepts only file URLs")
        }
        let output = try await data()
        do {
            try output.data.write(to: url, options: .atomic)
        } catch {
            throw HokusaiError.io(url: url, operation: .write, reason: error.localizedDescription)
        }
        return output.info
    }

    /// Evaluates every image of every page to straight 8-bit RGBA, keyed by page and item index.
    private func evaluateImages() async throws -> [VectorRenderer.ImageKey: RawImage] {
        var images: [VectorRenderer.ImageKey: RawImage] = [:]
        for (pageIndex, page) in pages.enumerated() {
            for (itemIndex, item) in page.items.enumerated() {
                guard case .image(let pipeline, _, _, _) = item else { continue }
                try Task.checkCancellation()
                images[.init(page: pageIndex, item: itemIndex)] = try await pipeline.raw(.rgba8)
            }
        }
        return images
    }
}
