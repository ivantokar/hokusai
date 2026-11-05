import Foundation
import Hokusai
import HokusaiPDF
import Testing

/// Vector PDF documents (#13). The structure is checked in the file itself (text operators, embedded
/// fonts with a ToUnicode map, page boxes) and the drawing by rasterising the result with libvips.
/// Rasterising the result needs a libvips with PDF input; CI's jobs expect it (HOKUSAI_EXPECT_CAPABILITIES).
private let pdfReadable = (try? Hokusai.capabilities().canDecode(.pdf)) ?? false

@Suite struct VectorPDFTests {
    // Cairo compresses page streams unless this variable is set when a surface is created; with it the
    // content stream is plain text and can be searched. It only changes how the same PDF is stored.
    init() { setenv("CAIRO_DEBUG_PDF", "1", 1) }

    private let navy = Color(red: 0.05, green: 0.1, blue: 0.3)
    private let white = Color.white

    private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }


    private func raster(_ pdf: Data, width: Int? = nil) async throws -> RawImage {
        try await Hokusai(data: pdf).raw(.rgba8)
    }

    private func solidImage(_ colour: [UInt8], _ width: Int = 20, _ height: Int = 10) throws -> Hokusai {
        var bytes: [UInt8] = []
        for _ in 0..<(width * height) { bytes += colour }
        return try Hokusai(raw: Data(bytes), width: width, height: height, format: .rgba8)
    }

    private func pixel(_ image: RawImage, _ x: Int, _ y: Int) -> [Int] {
        (0..<4).map { Int(image.data[image.data.startIndex + y * image.rowStride + x * 4 + $0]) }
    }

    // MARK: Structure

    @Test func aPageIsAPDFWithTheRequestedSize() async throws {
        let page = try VectorPage(size: .a4())
        let output = try await VectorDocument(page).data()
        #expect(output.data.prefix(5) == Data("%PDF-".utf8))
        #expect(output.info.pageCount == 1)
        #expect(output.info.byteCount == output.data.count)
        let body = text(output.data)
        #expect(body.contains("/MediaBox [ 0 0 595.276 841.89 ]") || body.contains("/MediaBox [ 0 0 595.276 841.890 ]") || body.contains("595.27"))
    }

    @Test func pagesKeepTheirOwnSizesAndOrder() async throws {
        let document = VectorDocument(pages: [
            try VectorPage(size: .letter()), try VectorPage(size: .points(width: 300, height: 200)),
            try VectorPage(size: .a4(.landscape)),
        ])
        let output = try await document.data()
        #expect(output.info.pageCount == 3)
        let body = text(output.data)
        #expect(body.components(separatedBy: "/Type /Page\n").count - 1 == 3 || body.components(separatedBy: "/Type /Page ").count - 1 >= 1)
        #expect(body.contains("612 792") && body.contains("300 200"))
    }

    @Test func textIsRealTextNotPixelsOrOutlines() async throws {
        let page = try VectorPage(size: .a4()).text(
            "Quarterly Performance", at: VectorPoint(x: 40, y: 60), width: 500,
            style: VectorTextStyle(size: 24, weight: .bold))
        let body = text(try await VectorDocument(page).data().data)
        #expect(body.contains("BT"), "a text object")
        #expect(body.contains("/ToUnicode"), "glyphs map back to characters, so the text can be selected")
        #expect(body.contains("/FontFile") || body.contains("/Type /Font"), "the font is embedded")
        #expect(!body.contains("/Subtype /Image"), "no raster was drawn for the text")
        // The ToUnicode map lists every character of the string.
        for scalar in Set("Quarterly Performance".unicodeScalars) where scalar != " " {
            let hex = String(format: "%04X", scalar.value)
            #expect(body.uppercased().contains("<\(hex)>"), "no ToUnicode entry for \(scalar)")
        }
    }

    @Test func aRasterPDFHasNoTextToSelect() async throws {
        let raster = try await solidImage([200, 50, 50, 255], 100, 60).pdf().data().data
        let body = text(raster)
        #expect(!body.contains("/ToUnicode"))
    }

    @Test func metadataIsWrittenToTheDocumentInfo() async throws {
        let metadata = PDFDocumentMetadata(title: "Q3 report", author: "Hokusai", subject: "Numbers", keywords: "a,b", creator: "tests")
        let output = try await VectorDocument(try VectorPage(), metadata: metadata).data()
        let body = text(output.data)
        for expected in ["Q3 report", "Hokusai", "Numbers", "a,b", "tests"] {
            #expect(body.contains(expected), "missing \(expected)")
        }
    }

    // MARK: Drawing

    @Test(.enabled(if: pdfReadable, "libvips cannot read PDFs in this build")) func aSolidBackgroundFillsThePage() async throws {
        let page = try VectorPage(size: .points(width: 100, height: 80)).background(.color(Color(red: 1, green: 0, blue: 0)))
        let image = try await raster(try await VectorDocument(page).data().data)
        #expect(image.width >= 90 && image.height >= 70)
        let centre = pixel(image, image.width / 2, image.height / 2)
        #expect(centre[0] > 240 && centre[1] < 15 && centre[2] < 15 && centre[3] == 255, "\(centre)")
    }

    @Test(.enabled(if: pdfReadable, "libvips cannot read PDFs in this build")) func aLinearGradientRunsFromOneColourToTheOther() async throws {
        let page = try VectorPage(size: .points(width: 200, height: 100))
            .background(.linearGradient(from: Color(red: 0, green: 0, blue: 0), to: white, angle: 0))
        let image = try await raster(try await VectorDocument(page).data().data)
        let left = pixel(image, 4, image.height / 2)[0], middle = pixel(image, image.width / 2, image.height / 2)[0]
        let right = pixel(image, image.width - 5, image.height / 2)[0]
        #expect(left < 40 && right > 215, "left \(left), right \(right)")
        #expect((90...170).contains(middle), "middle \(middle)")
        let top = pixel(image, image.width / 2, 3)[0], bottom = pixel(image, image.width / 2, image.height - 4)[0]
        #expect(abs(top - bottom) < 10, "an angle of 0 changes only across, not down")
    }

    @Test(.enabled(if: pdfReadable, "libvips cannot read PDFs in this build")) func aVerticalGradientChangesDownTheFrame() async throws {
        let page = try VectorPage(size: .points(width: 100, height: 200))
            .background(.linearGradient(from: Color(red: 0, green: 0, blue: 0), to: white))
        let image = try await raster(try await VectorDocument(page).data().data)
        #expect(pixel(image, 50, 4)[0] < 40 && pixel(image, 50, image.height - 5)[0] > 215)
    }

    @Test(.enabled(if: pdfReadable, "libvips cannot read PDFs in this build")) func rectanglesAreDrawnInOrderWithFillAndStroke() async throws {
        let page = try VectorPage(size: .points(width: 100, height: 100))
            .rectangle(VectorRect(x: 10, y: 10, width: 80, height: 80), fill: .color(Color(red: 1, green: 0, blue: 0)))
            .rectangle(VectorRect(x: 30, y: 30, width: 40, height: 40), fill: .color(Color(red: 0, green: 0, blue: 1)), stroke: VectorStroke(color: white, width: 2))
        let image = try await raster(try await VectorDocument(page).data().data)
        let scale = Double(image.width) / 100
        func at(_ x: Double, _ y: Double) -> [Int] { pixel(image, Int(x * scale), Int(y * scale)) }
        #expect(at(20, 20)[0] > 240 && at(20, 20)[2] < 15, "the red one")
        #expect(at(50, 50)[2] > 240 && at(50, 50)[0] < 15, "the blue one is on top")
        #expect(at(2, 2)[3] == 255 && at(2, 2)[0] > 240 && at(2, 2)[1] > 240, "outside is the page's white")
    }

    @Test(.enabled(if: pdfReadable, "libvips cannot read PDFs in this build")) func aLineIsDrawn() async throws {
        let page = try VectorPage(size: .points(width: 100, height: 100))
            .line(from: VectorPoint(x: 0, y: 50), to: VectorPoint(x: 100, y: 50), stroke: VectorStroke(color: Color(red: 0, green: 0, blue: 0), width: 6))
        let image = try await raster(try await VectorDocument(page).data().data)
        let scale = Double(image.width) / 100
        #expect(pixel(image, Int(50 * scale), Int(50 * scale))[0] < 40)
        #expect(pixel(image, Int(50 * scale), Int(10 * scale))[0] > 215)
    }

    @Test(.enabled(if: pdfReadable, "libvips cannot read PDFs in this build")) func imagesFitTheirFrame() async throws {
        let red = try solidImage([255, 0, 0, 255], 40, 20)     // 2:1
        let frame = VectorRect(x: 10, y: 10, width: 80, height: 80)
        func render(_ fit: VectorImageFit) async throws -> RawImage {
            let page = try VectorPage(size: .points(width: 100, height: 100)).image(red, frame: frame, fit: fit)
            return try await raster(try await VectorDocument(page).data().data)
        }
        for (fit, edgeIsRed) in [(VectorImageFit.contain, false), (.cover, true), (.fill, true)] {
            let image = try await render(fit)
            let scale = Double(image.width) / 100
            let centre = pixel(image, Int(50 * scale), Int(50 * scale))
            #expect(centre[0] > 240 && centre[1] < 15, "\(fit): the centre is the image")
            // Just inside the frame at its top: contain leaves letterbox bars (page white), the others fill it.
            let nearTop = pixel(image, Int(50 * scale), Int(14 * scale))
            #expect((nearTop[0] > 240 && nearTop[1] < 15) == edgeIsRed, "\(fit): near the top \(nearTop)")
            let outside = pixel(image, Int(3 * scale), Int(3 * scale))
            #expect(outside[1] > 240, "\(fit): nothing is drawn outside the frame")
        }
    }

    @Test(.enabled(if: pdfReadable, "libvips cannot read PDFs in this build")) func aPipelineIsEvaluatedAtWriteTime() async throws {
        let source = try solidImage([0, 0, 255, 255], 200, 200).resize(width: 50, height: 50, fit: .fill).negate()
        let page = try VectorPage(size: .points(width: 100, height: 100)).image(source, frame: VectorRect(x: 0, y: 0, width: 100, height: 100), fit: .fill)
        let image = try await raster(try await VectorDocument(page).data().data)
        let centre = pixel(image, image.width / 2, image.height / 2)
        #expect(centre[0] > 240 && centre[2] < 15, "negated blue is yellow: \(centre)")
    }

    @Test(.enabled(if: pdfReadable, "libvips cannot read PDFs in this build")) func textIsDrawnWhereItIsPlaced() async throws {
        let page = try VectorPage(size: .points(width: 200, height: 100)).text(
            "WWWW", at: VectorPoint(x: 10, y: 10), style: VectorTextStyle(size: 40, weight: .black))
        let image = try await raster(try await VectorDocument(page).data().data)
        let scale = Double(image.width) / 200
        var inked = 0, inkedBelow = 0
        for y in 0..<image.height { for x in 0..<image.width where pixel(image, x, y)[0] < 128 {
            if Double(y) / scale < 60 { inked += 1 } else { inkedBelow += 1 }
        } }
        #expect(inked > 200, "text appears in the upper part")
        #expect(inkedBelow == 0, "and not below it")
    }

    @Test func aNarrowWidthWrapsTheText() async throws {
        let words = "alpha beta gamma delta epsilon zeta eta theta"
        let narrow = try VectorPage(size: .a4()).text(.plain(words), at: VectorPoint(x: 20, y: 20), width: 80, style: VectorTextStyle(size: 14))
        let wide = try VectorPage(size: .a4()).text(.plain(words), at: VectorPoint(x: 20, y: 20), style: VectorTextStyle(size: 14))
        let narrowBody = text(try await VectorDocument(narrow).data().data)
        let wideBody = text(try await VectorDocument(wide).data().data)
        // Each wrapped line is positioned separately, so a narrow block has more text-positioning operators.
        func lines(_ body: String) -> Int { body.components(separatedBy: " Td").count + body.components(separatedBy: " Tm").count }
        #expect(lines(narrowBody) > lines(wideBody))
    }

    @Test func markupMixesStylesInOneBlock() async throws {
        let page = try VectorPage(size: .a4()).text(
            .markup("Plain <b>bold</b> and <span foreground=\"#ff0000\">red</span>"), at: VectorPoint(x: 20, y: 20))
        let body = text(try await VectorDocument(page).data().data)
        #expect(body.contains("/ToUnicode"))
    }

    // MARK: Validation and errors

    @Test func itemsAreValidatedWhenTheyAreAdded() throws {
        let page = try VectorPage()
        #expect(throws: HokusaiError.self) { try VectorPage(size: .points(width: 0, height: 100)) }
        #expect(throws: HokusaiError.self) { try VectorPage(size: .points(width: .nan, height: 100)) }
        #expect(throws: HokusaiError.self) { try VectorPage(size: .points(width: 20000, height: 100)) }
        #expect(throws: HokusaiError.self) { try page.background(.linearGradient(stops: [GradientStop(offset: 0, color: white)], angle: 0)) }
        #expect(throws: HokusaiError.self) {
            try page.background(.linearGradient(stops: [GradientStop(offset: 0.8, color: white), GradientStop(offset: 0.2, color: white)], angle: 0))
        }
        #expect(throws: HokusaiError.self) { try page.background(.color(Color(red: 2, green: 0, blue: 0))) }
        #expect(throws: HokusaiError.self) { try page.rectangle(VectorRect(x: 0, y: 0, width: 10, height: 10)) }
        #expect(throws: HokusaiError.self) { try page.rectangle(VectorRect(x: 0, y: 0, width: 0, height: 10), fill: .color(white)) }
        #expect(throws: HokusaiError.self) { try page.rectangle(VectorRect(x: 0, y: 0, width: 10, height: 10), fill: .color(white), cornerRadius: -1) }
        #expect(throws: HokusaiError.self) { try page.line(from: VectorPoint(x: 0, y: 0), to: VectorPoint(x: .infinity, y: 1), stroke: VectorStroke(color: white)) }
        #expect(throws: HokusaiError.self) { try page.line(from: VectorPoint(x: 0, y: 0), to: VectorPoint(x: 1, y: 1), stroke: VectorStroke(color: white, width: 0)) }
        #expect(throws: HokusaiError.self) { try page.text("", at: VectorPoint(x: 0, y: 0)) }
        #expect(throws: HokusaiError.self) { try page.text("x", at: VectorPoint(x: 0, y: 0), width: 0) }
        #expect(throws: HokusaiError.self) { try page.text("x", at: VectorPoint(x: .nan, y: 0)) }
        #expect(throws: HokusaiError.self) { try page.text("x", at: VectorPoint(x: 0, y: 0), style: VectorTextStyle(size: 0)) }
        #expect(throws: HokusaiError.self) { try page.text("x", at: VectorPoint(x: 0, y: 0), style: VectorTextStyle(lineSpacing: 9)) }
        #expect(throws: HokusaiError.self) { try page.text("x", at: VectorPoint(x: 0, y: 0), style: VectorTextStyle(family: "")) }
        let image = try solidImage([1, 2, 3, 255])
        #expect(throws: HokusaiError.self) { try page.image(image, frame: VectorRect(x: 0, y: 0, width: 10, height: 10), opacity: 2) }
        #expect(throws: HokusaiError.self) { try page.image(image, frame: VectorRect(x: 0, y: 0, width: -1, height: 10)) }
    }

    @Test func invalidMarkupIsReportedWhenWriting() async throws {
        let page = try VectorPage().text(.markup("<b>unclosed"), at: VectorPoint(x: 0, y: 0))
        await #expect(throws: HokusaiError.self) { try await VectorDocument(page).data() }
    }

    @Test func aDocumentNeedsAPage() async {
        await #expect(throws: HokusaiError.self) { try await VectorDocument(pages: []).data() }
    }

    @Test func aFailingImagePipelineFailsTheDocument() async throws {
        let broken = try Hokusai(data: Data("not an image".utf8))
        let page = try VectorPage().image(broken, frame: VectorRect(x: 0, y: 0, width: 50, height: 50))
        await #expect(throws: HokusaiError.self) { try await VectorDocument(page).data() }
    }

    // MARK: Files

    @Test func writeReplacesAnExistingFileAtomically() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vector-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("report.pdf")
        try Data("old".utf8).write(to: url)
        let info = try await VectorDocument(try VectorPage().text("hello", at: VectorPoint(x: 10, y: 10))).write(to: url)
        let written = try Data(contentsOf: url)
        #expect(written.prefix(5) == Data("%PDF-".utf8) && written.count == info.byteCount)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["report.pdf"])

        let missing = directory.appendingPathComponent("nope/report.pdf")
        await #expect(throws: HokusaiError.self) { try await VectorDocument(try VectorPage()).write(to: missing) }
        await #expect(throws: HokusaiError.self) { try await VectorDocument(try VectorPage()).write(to: URL(string: "https://example.com/x.pdf")!) }
    }

    @Test func aBrandedStatisticsReportComesOutAsOneDocument() async throws {
        let hero = try solidImage([20, 120, 200, 255], 400, 160)
        let cover = try VectorPage(size: .a4())
            .background(.linearGradient(from: navy, to: Color(red: 0.0, green: 0.5, blue: 0.5)))
            .image(hero, frame: VectorRect(x: 40, y: 40, width: 515, height: 200), fit: .cover)
            .text("Quarterly Performance", at: VectorPoint(x: 40, y: 270), width: 515,
                  style: VectorTextStyle(size: 30, weight: .bold, color: white))
            .text("Revenue grew <b>18%</b> over the previous quarter.", at: VectorPoint(x: 40, y: 330), width: 515,
                  style: VectorTextStyle(size: 14, color: white, lineSpacing: 1.3))
        let cardStroke = VectorStroke(color: white, width: 1)
        var summary = try VectorPage(size: .a4()).background(.color(white))
        for (index, label) in ["Revenue", "Margin", "Churn"].enumerated() {
            let x = 40 + Double(index) * 175
            summary = try summary
                .rectangle(VectorRect(x: x, y: 60, width: 160, height: 90), fill: .color(navy), stroke: cardStroke, cornerRadius: 8)
                .text(.plain(label), at: VectorPoint(x: x + 14, y: 76), style: VectorTextStyle(size: 12, color: white))
        }
        let metadata = PDFDocumentMetadata(title: "Quarterly Performance", author: "Hokusai")
        let output = try await VectorDocument(pages: [cover, summary], metadata: metadata).data()
        #expect(output.info.pageCount == 2)
        #expect(text(output.data).contains("Quarterly Performance"))
    }
}
