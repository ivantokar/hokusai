import Foundation
import Hokusai
import Testing

/// Whether this libvips build can read PDFs back, which the structural tests use.
private let pdfReadable = (try? Hokusai.capabilities().canDecode(.pdf)) ?? false

/// Raster-PDF output (#44), black box: page geometry, placement, background,
/// sink parity and failures. `%PDF-` alone is never the proof of a document;
/// structure is checked on the bytes and, where libvips can read PDFs, by
/// reading the document back as an independent oracle.
@Suite struct PDFSemanticsTests {
    /// A fixed creation date makes the PDF bytes reproducible.
    private let fixed = PDFDocumentMetadata(creationDate: Date(timeIntervalSince1970: 1_700_000_000))

    /// 320×200 photo-like fixture.
    private func photo() throws -> Hokusai {
        try Hokusai(data: fixtureData(named: "landscape-asym", ext: "jpg"))
    }

    private func temporaryURL(_ name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hokusai-pdf-\(UUID().uuidString)-\(name)")
    }

    private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    private func expectWellFormed(_ data: Data, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(data.starts(with: Data("%PDF-".utf8)), sourceLocation: sourceLocation)
        let tail = text(data.suffix(32)).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(tail.hasSuffix("%%EOF"), "the trailer ends the file", sourceLocation: sourceLocation)
        #expect(text(data.suffix(64)).contains("startxref"), sourceLocation: sourceLocation)
    }

    /// Page sizes read back by libvips' PDF loader at 72 DPI, so in points.
    private func pages(of data: Data) async throws -> [(width: Int, height: Int)] {
        let count = try await Hokusai(data: data).metadata().pages.count
        var sizes: [(width: Int, height: Int)] = []
        for index in 0..<count {
            let page = try await Hokusai(data: data, options: InputOptions(page: index)).metadata()
            sizes.append((page.width, page.height))
        }
        return sizes
    }

    private func details(_ pipeline: Hokusai) async throws -> PDFOutputDetails {
        try #require(try await pipeline.data().info.pdf)
    }

    // MARK: - Page geometry

    @Test func imagePagesDeriveTheirSizeFromPixelsAndDPI() async throws {
        let at72 = try await details(photo().pdf(pageSize: .image()))
        #expect((at72.pageWidth, at72.pageHeight) == (320, 200))

        let at144 = try await details(photo().pdf(pageSize: .image(dpi: 144)))
        #expect((at144.pageWidth, at144.pageHeight) == (160, 100))

        let margined = try await details(photo().pdf(pageSize: .image(dpi: 144), margins: .all(10)))
        #expect((margined.pageWidth, margined.pageHeight) == (180, 120), "margins grow an image-sized page")
    }

    @Test func standardPagesHaveTheirPhysicalSize() async throws {
        let a4 = try await details(photo().pdf(pageSize: .a4()))
        let landscape = try await details(photo().pdf(pageSize: .a4(.landscape)))
        #expect(abs(a4.pageWidth - 595.276) < 0.001 && abs(a4.pageHeight - 841.890) < 0.001)
        #expect(abs(landscape.pageWidth - 841.890) < 0.001 && abs(landscape.pageHeight - 595.276) < 0.001)

        let letter = try await details(photo().pdf(pageSize: .letter(.landscape)))
        #expect((letter.pageWidth, letter.pageHeight) == (792, 612))

        let custom = try await details(photo().pdf(pageSize: .points(width: 600, height: 800)))
        #expect((custom.pageWidth, custom.pageHeight) == (600, 800))
    }

    @Test func outputInfoKeepsRasterPixelsAndOnePage() async throws {
        let output = try await photo().pdf(pageSize: .a4(), metadata: fixed).data()
        #expect(output.info.format == .pdf)
        #expect((output.info.width, output.info.height) == (320, 200), "raster pixels, not points")
        #expect(output.info.byteCount == output.data.count)
        #expect(output.info.pdf?.pageCount == 1)
    }

    @Test func nonPDFOutputsCarryNoPageDetails() async throws {
        #expect(try await photo().png().data().info.pdf == nil)
    }

    // MARK: - Documents

    @Test(.enabled(if: pdfReadable, "libvips cannot read PDFs in this build"))
    func aDocumentIsStructurallyValidWithTheRequestedPage() async throws {
        let output = try await photo().pdf(pageSize: .a4(), metadata: fixed).data()
        expectWellFormed(output.data)

        let read = try await pages(of: output.data)
        #expect(read.count == 1)
        #expect(abs(read[0].width - 595) <= 1 && abs(read[0].height - 842) <= 1, "A4 in points")
    }

    @Test(.enabled(if: pdfReadable, "libvips cannot read PDFs in this build"))
    func imageDPIPagesReadBackAtTheirDeclaredSize() async throws {
        let output = try await photo().pdf(pageSize: .image(dpi: 144)).data()
        let read = try await pages(of: output.data)
        #expect(read.count == 1)
        #expect(abs(read[0].width - 160) <= 1 && abs(read[0].height - 100) <= 1)
    }

    @Test func everyOutputIsAWellFormedDocument() async throws {
        expectWellFormed(try await photo().pdf(metadata: fixed).data().data)
    }

    @Test func dataAndFileOutputsAreTheSameDocument() async throws {
        let pipeline = try photo().pdf(pageSize: .letter(), margins: .all(18), background: .white, metadata: fixed)
        let url = temporaryURL("same.pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        let memory = try await pipeline.data()
        let info = try await pipeline.write(to: url)
        let file = try Data(contentsOf: url)

        #expect(memory.data == file, "reproducible with a fixed creation date")
        #expect(info == memory.info)
        #expect(info.byteCount == file.count)
        expectWellFormed(file)
    }

    @Test func documentMetadataIsOptInAndNeverCopiedFromTheSource() async throws {
        // The source carries EXIF, XMP and IPTC that all mention "hokusai".
        let source = try Hokusai(data: fixtureData(named: "metadata-rich", ext: "jpg"))

        let plain = try await source.pdf(metadata: fixed).data().data
        #expect(!text(plain).contains("hokusai"))

        let described = try await source.pdf(metadata: PDFDocumentMetadata(
            title: "Quarterly report", author: "A. Writer", subject: "Numbers", keywords: "q3, finance",
            creator: "Hokusai tests", creationDate: fixed.creationDate)).data().data
        #expect(described != plain, "requested document metadata changes the document")
        expectWellFormed(described)
    }

    // MARK: - Placement and background

    @Test(.enabled(if: pdfReadable, "libvips cannot read PDFs in this build"))
    func theBackgroundFillsTheMarginsAndTheImageSitsInside() async throws {
        // A solid blue square on a 100×100 pt page with 20 pt margins, on red.
        let blue = Raster.solid(width: 10, height: 10, [0, 0, 255, 255])
        let output = try await Hokusai(data: tiffData(blue))
            .pdf(pageSize: .points(width: 100, height: 100), margins: .all(20),
                 background: Color(red: 1, green: 0, blue: 0), metadata: fixed)
            .data()
        let page = try await rasterize(encoded: output.data)

        #expect((page.width, page.height) == (100, 100))
        let corner = page.pixel(5, 5)
        #expect(corner[0] > 240 && corner[1] < 15 && corner[2] < 15, "margin shows the background")
        let centre = page.pixel(50, 50)
        #expect(centre[2] > 240 && centre[0] < 15, "the image fills the area inside the margins")
    }

    // MARK: - Validation

    @Test func invalidPageOptionsAreRejectedBeforeAnyWork() throws {
        let image = try photo()
        let invalid: [(String, () throws -> Hokusai)] = [
            ("pageSize.dpi", { try image.pdf(pageSize: .image(dpi: 0)) }),
            ("pageSize.dpi", { try image.pdf(pageSize: .image(dpi: .nan)) }),
            ("pageSize.width", { try image.pdf(pageSize: .points(width: -1, height: 10)) }),
            ("pageSize.height", { try image.pdf(pageSize: .points(width: 10, height: .infinity)) }),
            ("margins.top", { try image.pdf(margins: PDFMargins(top: -1)) }),
            ("margins.trailing", { try image.pdf(margins: PDFMargins(trailing: .nan)) }),
            ("maxEffectiveDPI", { try image.pdf(maxEffectiveDPI: 0) }),
            ("color", { try image.pdf(background: Color(red: 2, green: 0, blue: 0)) }),
        ]
        for (field, make) in invalid {
            do {
                _ = try make()
                Issue.record("expected \(field) to be rejected")
            } catch HokusaiError.invalidOption(let name, _) {
                #expect(name == field)
            }
        }
    }

    @Test func marginsThatLeaveNoRoomFailWhenTheImageIsKnown() async throws {
        let pipeline = try photo().pdf(pageSize: .points(width: 100, height: 100), margins: .all(60))
        do {
            _ = try await pipeline.data()
            Issue.record("expected margins to be rejected")
        } catch HokusaiError.invalidOption(let name, _) {
            #expect(name == "margins")
        }
    }

    // MARK: - Failures

    @Test func anUnwritableDestinationIsAWriteIOError() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("missing-\(UUID().uuidString)")
            .appendingPathComponent("a.pdf")
        do {
            _ = try await photo().pdf().write(to: url)
            Issue.record("expected the write to fail")
        } catch HokusaiError.io(let failedURL, let operation, let reason) {
            #expect(failedURL == url)
            #expect(operation == .write)
            #expect(!reason.isEmpty)
        }
    }

    @Test func aFailedPipelineLeavesNoPartialPDF() async throws {
        let url = temporaryURL("never.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let broken = try Hokusai(data: fixtureData(named: "truncated", ext: "jpg")).pdf()

        do {
            _ = try await broken.write(to: url)
            Issue.record("expected the truncated source to fail")
        } catch HokusaiError.decode {
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aCancelledWriteThrowsCancellationAndLeavesNoFile() async throws {
        let url = temporaryURL("cancelled.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let expensive = try photo()
            .resize(width: 12000, height: 7500, fit: .fill)
            .blur(sigma: 50)
            .pdf()

        let task = Task { try await expensive.write(to: url) }
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch is CancellationError {
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
