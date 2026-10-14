import Foundation
import Testing
import CCairo
@testable import Hokusai

/// Whether this libvips build can read PDFs back, which the structural tests use.
private let pdfReadable = (try? Hokusai.capabilities().canDecode(.pdf)) ?? false

/// Raster-PDF output (#44): page geometry, one-buffer rasters, shared sinks.
@Suite struct PDFOutputTests {
    init() throws { try Hokusai.initialize() }

    // MARK: - Helpers

    /// A fixed creation date makes the PDF bytes reproducible.
    private let fixed = PDFDocumentMetadata(creationDate: Date(timeIntervalSince1970: 1_700_000_000))

    private func photo() throws -> Hokusai {
        try Hokusai(data: loadFixtureData(named: "landscape-asym", ext: "jpg"))
    }

    private func temporaryURL(_ name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hokusai-pdf-\(UUID().uuidString)-\(name)")
    }

    private func text(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    /// Page sizes in pixels at 72 DPI (so points, rounded up), read back by
    /// libvips' PDF loader. An independent reader is used because Cairo packs
    /// the page tree into compressed object streams, so the text of the file
    /// does not show its pages.
    private func pages(of data: Data) async throws -> [(width: Int, height: Int)] {
        let count = try await Hokusai(data: data).metadata().pages.count
        var sizes: [(width: Int, height: Int)] = []
        for index in 0..<count {
            let page = try await Hokusai(data: data, options: InputOptions(page: index)).metadata()
            sizes.append((page.width, page.height))
        }
        return sizes
    }

    /// Structural checks that do not depend on a PDF reader.
    private func expectWellFormed(_ data: Data, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(data.starts(with: Data("%PDF-".utf8)), sourceLocation: sourceLocation)
        let tail = text(data.suffix(32)).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(tail.hasSuffix("%%EOF"), "the trailer ends the file", sourceLocation: sourceLocation)
        #expect(text(data.suffix(64)).contains("startxref"), sourceLocation: sourceLocation)
    }

    // MARK: - Page geometry

    @Test func imagePagesDeriveTheirSizeFromPixelsAndDPI() throws {
        let at72 = try PDFLayout.resolve(pixelWidth: 144, pixelHeight: 72, options: PDFOptions(pageSize: .image()))
        #expect((at72.pageWidth, at72.pageHeight) == (144, 72))
        #expect((at72.x, at72.y, at72.width, at72.height) == (0, 0, 144, 72))

        let at144 = try PDFLayout.resolve(pixelWidth: 144, pixelHeight: 72, options: PDFOptions(pageSize: .image(dpi: 144)))
        #expect((at144.pageWidth, at144.pageHeight) == (72, 36))

        // Margins add to an image page; the raster still fills the rest exactly.
        let margined = try PDFLayout.resolve(
            pixelWidth: 144, pixelHeight: 72, options: PDFOptions(pageSize: .image(dpi: 144), margins: .all(10)))
        #expect((margined.pageWidth, margined.pageHeight) == (92, 56))
        #expect((margined.x, margined.y, margined.width, margined.height) == (10, 10, 72, 36))
    }

    @Test func fixedPagesAspectFitCentredByDefault() throws {
        let layout = try PDFLayout.resolve(pixelWidth: 200, pixelHeight: 100, options: PDFOptions(pageSize: .points(width: 600, height: 800)))
        #expect((layout.pageWidth, layout.pageHeight) == (600, 800))
        #expect((layout.width, layout.height) == (600, 300))
        #expect((layout.x, layout.y) == (0, 250))

        let a4 = try PDFLayout.resolve(pixelWidth: 10, pixelHeight: 10, options: PDFOptions(pageSize: .a4()))
        let landscape = try PDFLayout.resolve(pixelWidth: 10, pixelHeight: 10, options: PDFOptions(pageSize: .a4(.landscape)))
        #expect((a4.pageWidth, a4.pageHeight) == (595.276, 841.890))
        #expect((landscape.pageWidth, landscape.pageHeight) == (841.890, 595.276))

        let letter = try PDFLayout.resolve(pixelWidth: 10, pixelHeight: 10, options: PDFOptions(pageSize: .letter(.landscape)))
        #expect((letter.pageWidth, letter.pageHeight) == (792, 612))
    }

    @Test func marginsAndAnchorsPlaceTheRaster() throws {
        let base = PDFOptions(pageSize: .points(width: 400, height: 400), margins: .all(50))
        let centred = try PDFLayout.resolve(pixelWidth: 200, pixelHeight: 100, options: base)
        #expect((centred.width, centred.height) == (300, 150))
        #expect((centred.x, centred.y) == (50, 125))

        var topLeft = base
        topLeft.anchor = .northWest
        let corner = try PDFLayout.resolve(pixelWidth: 200, pixelHeight: 100, options: topLeft)
        #expect((corner.x, corner.y) == (50, 50))

        var bottomRight = base
        bottomRight.anchor = .southEast
        let far = try PDFLayout.resolve(pixelWidth: 200, pixelHeight: 100, options: bottomRight)
        #expect((far.x, far.y) == (50, 200))

        var uneven = PDFOptions(pageSize: .points(width: 400, height: 400))
        uneven.margins = PDFMargins(top: 10, leading: 40, bottom: 30, trailing: 20)
        let asymmetric = try PDFLayout.resolve(pixelWidth: 100, pixelHeight: 100, options: uneven)
        #expect((asymmetric.width, asymmetric.height) == (340, 340))
        // 340 wide fits exactly; 20 points are free vertically and split evenly.
        #expect((asymmetric.x, asymmetric.y) == (40, 20))
    }

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
        var thrown: Error?
        do { _ = try await pipeline.data() } catch { thrown = error }
        guard case HokusaiError.invalidOption(let name, _)? = thrown else {
            Issue.record("expected invalidOption, got \(String(describing: thrown))")
            return
        }
        #expect(name == "margins")
    }

    // MARK: - Documents

    @Test(.enabled(if: pdfReadable, "libvips cannot read PDFs in this build"))
    func aDocumentIsStructurallyValidWithTheRequestedPage() async throws {
        let output = try await photo().pdf(pageSize: .a4(), metadata: fixed).data()
        expectWellFormed(output.data)

        let read = try await pages(of: output.data)
        #expect(read.count == 1)
        #expect(abs(read[0].width - 595) <= 1 && abs(read[0].height - 842) <= 1, "A4 in points")

        #expect(output.info.format == .pdf)
        #expect((output.info.width, output.info.height) == (320, 200), "raster pixels, not points")
        #expect(output.info.size == output.data.count)
        let pdf = try #require(output.info.pdf)
        #expect(pdf.pageCount == 1)
        #expect(abs(pdf.pageWidth - 595.276) < 0.001 && abs(pdf.pageHeight - 841.89) < 0.001)
    }

    @Test func everyOutputIsAWellFormedDocumentWithAnInfoBlock() async throws {
        let output = try await photo().pdf(metadata: fixed).data()
        expectWellFormed(output.data)
        #expect(text(output.data).contains("/Producer") || output.data.range(of: Data("ObjStm".utf8)) != nil)
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
        #expect(info.size == file.count)
        expectWellFormed(file)
    }

    @Test func aFileWriteGoesStraightToTheDestination() async throws {
        let url = temporaryURL("direct.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let trace = PlanTrace()
        let pipeline = try photo().pdf()

        let info = try Evaluator.write(
            pipeline.plan, pipeline.terminal, as: pipeline.terminal.encoder!, to: url,
            context: EvaluationContext(trace: trace))

        #expect(trace.events.contains(.sinkSelected("file pdf")))
        let written = try Data(contentsOf: url)
        #expect(info.size == written.count)
    }

    @Test func documentMetadataIsOptInAndNeverCopiedFromTheSource() async throws {
        // This source carries EXIF, XMP and IPTC that all mention "hokusai".
        // The Hokusai code never reads them into the PDF; the Info dictionary
        // may be compressed, so the check below is a regression guard rather
        // than proof, and the guarantee is that no source metadata is passed on.
        let source = try Hokusai(data: loadFixtureData(named: "metadata-rich", ext: "jpg"))

        let plain = try await source.pdf(metadata: fixed).data().data
        #expect(!text(plain).contains("hokusai"))

        let described = try await source.pdf(metadata: PDFDocumentMetadata(
            title: "Quarterly report", author: "A. Writer", subject: "Numbers", keywords: "q3, finance",
            creator: "Hokusai tests", creationDate: fixed.creationDate)).data().data
        #expect(described != plain)
        expectWellFormed(described)
    }

    // MARK: - Raster conversion

    @Test func rastersArePremultipliedWithRoundingInCairoByteOrder() async throws {
        let source = try NativeImage.open(data: loadFixtureData(named: "rgba-alpha", ext: "png"))
        let raster = try source.cairoRaster()

        #expect((raster.width, raster.height) == (3, 1))
        #expect(raster.stride == Int(hokusai_cairo_argb32_stride(3)))
        let pixels = raster.pixels.assumingMemoryBound(to: UInt8.self)
        let bytes = Array(UnsafeBufferPointer(start: pixels, count: raster.stride))

        // Source pixels are (200, 100, 50) at alpha 255, 128, and 0.
        // Native little-endian ARGB32 is B, G, R, A in memory.
        #expect(Array(bytes[0..<4]) == [50, 100, 200, 255])
        #expect(Array(bytes[4..<8]) == [25, 50, 100, 128], "50×128/255 = 25.1, 100×128/255 = 50.2, 200×128/255 = 100.4")
        #expect(Array(bytes[8..<12]) == [0, 0, 0, 0])
    }

    @Test(arguments: [1, 2, 3, 5, 7, 31, 100])
    func theRasterStrideComesFromCairo(width: Int) throws {
        let stride = Int(hokusai_cairo_argb32_stride(Int32(width)))
        #expect(stride >= width * 4 && stride % 4 == 0)
    }

    @Test func greyscaleAndWideSamplesBecomeRGBARasters() async throws {
        for name in ["pixel", "rgb16"] {
            let raster = try NativeImage.open(data: loadFixtureData(named: name, ext: "png")).cairoRaster()
            #expect(raster.stride == raster.width * 4)
        }
        let cmyk = try NativeImage.open(data: loadFixtureData(named: "cmyk", ext: "jpg")).cairoRaster()
        #expect((cmyk.width, cmyk.height) == (16, 16))
    }

    @Test func transparencyIsKeptUnlessABackgroundIsGiven() async throws {
        let translucent = try Hokusai(data: loadFixtureData(named: "rgba-alpha", ext: "png"))
        let opaque = try photo()

        let masked = try await translucent.pdf(metadata: fixed).data().data
        let solid = try await opaque.pdf(metadata: fixed).data().data
        let filled = try await translucent.pdf(background: .white, metadata: fixed).data().data

        // Alpha becomes a soft mask on the image object; an opaque image needs none.
        #expect(masked.range(of: Data("/SMask".utf8)) != nil, "transparent pixels stay transparent")
        #expect(solid.range(of: Data("/SMask".utf8)) == nil)
        // A background paints the page behind the image instead of dropping alpha.
        #expect(filled != masked)
        #expect(filled.range(of: Data("/SMask".utf8)) != nil)
        expectWellFormed(masked)
        expectWellFormed(filled)
    }

    // MARK: - Effective resolution

    @Test func resamplingIsOptInAndHonoursTheCap() async throws {
        // 320 px across 2 inches (144 pt) is 160 DPI.
        let page = PDFPageSize.points(width: 144, height: 144)
        let untouched = try await photo().pdf(pageSize: page).data()
        #expect((untouched.info.width, untouched.info.height) == (320, 200), "a physical page never resamples by itself")

        let capped = try await photo().pdf(pageSize: page, maxEffectiveDPI: 80).data()
        #expect(capped.info.width == 160, "320 px at 160 DPI capped to 80 DPI")
        #expect(capped.info.height == 100)

        let belowCap = try await photo().pdf(pageSize: page, maxEffectiveDPI: 300).data()
        #expect(belowCap.info.width == 320, "a raster under the cap is left alone")
    }

    // MARK: - Failures

    @Test(arguments: ["a.pdf"])
    func anUnwritableDestinationIsAWriteIOError(name: String) async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("missing-\(UUID().uuidString)")
            .appendingPathComponent(name)
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
        let broken = try Hokusai(data: loadFixtureData(named: "truncated", ext: "jpg")).pdf()

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
        let expensive = try Hokusai(data: loadFixtureData(named: "landscape-asym", ext: "jpg"))
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

    @Test func aSinkThatRefusesBytesIsAnEncodeFailureWithCairoDiagnostics() throws {
        // A cancelled evaluation makes the sink refuse bytes, which Cairo
        // reports as a write error. The description comes from Cairo itself.
        let sink = PDFOutputSink(destination: .memory, isCancelled: { true })
        let image = try NativeImage.open(data: loadFixtureData(named: "landscape-asym", ext: "jpg"))
        do {
            _ = try image.writePDF(PDFOptions(), into: sink)
            Issue.record("expected the document to fail")
        } catch HokusaiError.encode(let context) {
            #expect(context.operation == "encode pdf")
            #expect(context.diagnostic?.isEmpty == false)
        }
    }

    #if os(Linux)
    @Test func aFullDiskIsAWriteIOError() async throws {
        let url = URL(fileURLWithPath: "/dev/full")
        do {
            _ = try await photo().pdf().write(to: url)
            Issue.record("expected ENOSPC")
        } catch HokusaiError.io(let failedURL, let operation, let reason) {
            #expect(failedURL == url)
            #expect(operation == .write)
            #expect(reason.lowercased().contains("space"))
        }
        #expect(FileManager.default.fileExists(atPath: "/dev/full"))
    }
    #endif

    // MARK: - Capabilities

    @Test func pdfOutputIsIndependentOfPDFInput() throws {
        let inputOnly = RuntimeCapabilities(libvipsVersion: "test", inputFormats: [.pdf], outputFormats: [.jpeg], textRendering: false)
        let outputOnly = RuntimeCapabilities(libvipsVersion: "test", inputFormats: [.jpeg], outputFormats: [.pdf], textRendering: false)

        #expect(throws: HokusaiError.self) {
            _ = try Evaluator.selectEncoder(.pdf(), TerminalConfig(), capabilities: inputOnly)
        }
        _ = try Evaluator.selectEncoder(.pdf(), TerminalConfig(), capabilities: outputOnly)
    }

    // MARK: - Multiple pages

    @Test(.enabled(if: pdfReadable, "libvips cannot read PDFs in this build"))
    func theWriterEmitsSeveralPagesOfDifferentSizes() async throws {
        let sink = PDFOutputSink(destination: .memory)
        let writer = try PDFDocumentWriter(
            sink: sink, firstPage: (200, 100),
            metadata: PDFDocumentMetadata(creationDate: Date(timeIntervalSince1970: 1_700_000_000)))

        let small = try NativeImage.open(data: loadFixtureData(named: "landscape-asym", ext: "jpg")).cairoRaster()
        let tiny = try NativeImage.open(data: loadFixtureData(named: "rgba-alpha", ext: "png")).cairoRaster()
        try writer.addPage(small, layout: PDFPageLayout(pageWidth: 200, pageHeight: 100, x: 0, y: 0, width: 160, height: 100), background: nil)
        try writer.addPage(tiny, layout: PDFPageLayout(pageWidth: 300, pageHeight: 150, x: 0, y: 0, width: 300, height: 100), background: .white)
        let pageCount = try writer.finish()
        #expect(sink.complete(success: true) == nil)

        let data = sink.takeData()
        expectWellFormed(data)
        #expect(pageCount == 2)
        let read = try await pages(of: data)
        #expect(read.count == 2)
        #expect(abs(read[0].width - 200) <= 1 && abs(read[0].height - 100) <= 1)
        #expect(abs(read[1].width - 300) <= 1 && abs(read[1].height - 150) <= 1)
    }
}
