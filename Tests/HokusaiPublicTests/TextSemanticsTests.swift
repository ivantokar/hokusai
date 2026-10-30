import Foundation
import Hokusai
import Testing

/// Text (#38), black box. These tests check the typed contract (escaping,
/// wrapping, fit, alignment, line spacing, stroke and shadow geometry,
/// rotation, placement) through dimensions and alpha, never glyph bytes, so
/// they hold across platform fonts.
@Suite struct TextSemanticsTests {
    private let sentence: TextContent = "the quick brown fox jumps over the lazy dog"

    private func size(_ pipeline: Hokusai) async throws -> (width: Int, height: Int) {
        let metadata = try await pipeline.metadata()
        return (metadata.width, metadata.height)
    }

    private func text(_ content: TextContent, layout: TextLayout = .natural, style: TextStyle = TextStyle()) async throws -> (width: Int, height: Int) {
        try await size(Hokusai.text(content, layout: layout, style: style))
    }

    /// First and last columns holding visible ink within `rows`.
    private func inkColumns(_ raster: Raster, rows: Range<Int>) -> (first: Int, last: Int)? {
        var first: Int?, last: Int?
        for y in rows where y < raster.height {
            for x in 0..<raster.width where raster.pixel(x, y)[3] > 64 {
                first = min(first ?? x, x)
                last = max(last ?? x, x)
            }
        }
        guard let first, let last else { return nil }
        return (first, last)
    }

    private func strongestPixel(_ raster: Raster) -> [UInt8] {
        var strongest: [UInt8] = [0, 0, 0, 0]
        for y in 0..<raster.height {
            for x in 0..<raster.width where raster.pixel(x, y)[3] > strongest[3] { strongest = raster.pixel(x, y) }
        }
        return strongest
    }

    // MARK: - Standalone source

    @Test func textIsAnOrdinaryPipelineThatEncodesOnItsOwn() async throws {
        let output = try await Hokusai.text("Hello").png().data()
        #expect(output.info.width > 10 && output.info.height > 5)
        #expect(try await Hokusai.text("Hello").metadata().width == output.info.width)
    }

    @Test func textRendersTheRequestedColourOverTransparency() async throws {
        let raster = try await rasterize(Hokusai.text("MM", style: TextStyle(fontSize: 40, color: Color(red: 1, green: 0, blue: 0))))
        let strongest = strongestPixel(raster)
        #expect(strongest[3] > 200 && strongest[0] > 200 && strongest[1] < 60 && strongest[2] < 60)
        let faintest = (0..<raster.height).flatMap { y in (0..<raster.width).map { raster.pixel($0, y)[3] } }.min() ?? 255
        #expect(faintest < 32, "text is drawn over a transparent canvas")
    }

    @Test func aTextPipelineCanBeTransformedLikeAnyOther() async throws {
        let output = try await Hokusai.text("Hello", style: TextStyle(fontSize: 40)).resize(width: 30).png().data()
        #expect(output.info.width == 30)
    }

    @Test func unicodeTextRenders() async throws {
        let rendered = try await text("Привіт 世界 ✓")
        #expect(rendered.width > 20 && rendered.height > 5)
    }

    // MARK: - Content

    @Test func plainTextIsEscapedSoMarkupCharactersAreLiteral() async throws {
        #expect(try await text(.plain("<b>x</b> & <")).width > 20)
        #expect(try await text(.plain("<b>")).width > 5, "stray markup characters are not an error")
    }

    @Test func markupIsInterpretedOnlyWhenAskedFor() async throws {
        let plain = try await text(.plain("<span size=\"300%\">A</span>"))
        let marked = try await text(.markup("<span size=\"300%\">A</span>"))
        let single = try await text(.plain("A"))
        #expect(marked.height > single.height)
        #expect(plain.width > marked.width)
    }

    @Test func invalidMarkupFailsWhenEvaluated() async throws {
        let broken = try Hokusai.text(.markup("<b>unclosed"))
        await #expect(throws: HokusaiError.self) { try await broken.metadata() }
    }

    // MARK: - Layout

    @Test func widthWrapsWordsWithinTheWidth() async throws {
        let style = TextStyle(fontSize: 20)
        let one = try await text("the", style: style)
        let wrapped = try await text(sentence, layout: .width(120), style: style)
        #expect(wrapped.width <= 120)
        #expect(wrapped.height > one.height * 2)
    }

    @Test func noWrapKeepsASingleLine() async throws {
        let style = TextStyle(fontSize: 20)
        let natural = try await text(sentence, style: style)
        let unwrapped = try await text(sentence, layout: .width(120, wrap: .none), style: style)
        #expect(unwrapped.height == natural.height)
    }

    @Test func characterWrapBreaksALongWordThatWordWrapKeeps() async throws {
        let long: TextContent = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"
        let style = TextStyle(fontSize: 20)
        let one = try await text(long, style: style)
        let byWord = try await text(long, layout: .width(100, wrap: .word), style: style)
        let byCharacter = try await text(long, layout: .width(100, wrap: .character), style: style)
        let both = try await text(long, layout: .width(100, wrap: .wordCharacter), style: style)
        #expect(byWord.height == one.height)
        #expect(byCharacter.height > one.height)
        #expect(both.height > one.height)
    }

    @Test func fitStaysInsideTheBoxAndFillsIt() async throws {
        let fitted = try await text("Fit me", layout: .fit(width: 300, height: 100))
        #expect(fitted.width <= 300 && fitted.height <= 100)
        #expect(fitted.width > 100 || fitted.height > 50)
    }

    @Test func fitIgnoresTheStyleDPI() async throws {
        let low = try await text("Fit me", layout: .fit(width: 200, height: 80), style: TextStyle(dpi: 72))
        let high = try await text("Fit me", layout: .fit(width: 200, height: 80), style: TextStyle(dpi: 600))
        #expect(low == high)
    }

    @Test func lineHeightIsAMultipleOfTheNaturalPitch() async throws {
        let style = { (multiple: Double) in TextStyle(fontSize: 30, lineHeight: multiple) }
        let two: TextContent = "Ag\nAg"
        let one = try await text("Ag", style: style(1))
        let normal = try await text(two, style: style(1))
        let double = try await text(two, style: style(2))
        let tight = try await text(two, style: style(0.5))
        let pitch = normal.height - one.height
        #expect(abs((double.height - normal.height) - pitch) <= 2)
        #expect(abs((normal.height - tight.height) - pitch / 2) <= 2)
    }

    @Test func alignmentMovesShortLinesWithinTheBox() async throws {
        let content: TextContent = "i\nWWWWWWWW"
        func columns(_ alignment: TextAlignment) async throws -> (first: Int, last: Int) {
            let raster = try await rasterize(Hokusai.text(content, style: TextStyle(fontSize: 30, alignment: alignment)))
            return try #require(inkColumns(raster, rows: 0..<(raster.height / 3)))
        }
        let left = try await columns(.left), centre = try await columns(.center), right = try await columns(.right)
        #expect(left.first < centre.first && centre.first < right.first)
    }

    @Test func justifyStretchesWrappedLinesToTheWidth() async throws {
        func firstLineEnd(_ justify: Bool) async throws -> Int {
            let raster = try await rasterize(Hokusai.text(sentence, layout: .width(160), style: TextStyle(fontSize: 18, justify: justify)))
            return try #require(inkColumns(raster, rows: 0..<14)).last
        }
        let ragged = try await firstLineEnd(false)
        let justified = try await firstLineEnd(true)
        #expect(justified >= ragged)
        #expect(justified >= 150)
    }

    // MARK: - Stroke, shadow, rotation

    @Test func strokeGrowsTheCanvasByItsRadiusOnEverySide() async throws {
        let plain = try await text("Hi", style: TextStyle(fontSize: 40))
        let stroked = try await text("Hi", style: TextStyle(fontSize: 40, stroke: TextStroke(color: .white, width: 4)))
        #expect(stroked.width == plain.width + 8 && stroked.height == plain.height + 8)
    }

    /// Regression: the outline was dilated with a mask that required the
    /// surroundings to be clear, so the whole canvas came out as stroke colour.
    @Test(arguments: [1.0, 2.0, 3.0, 4.0])
    func strokeOutlinesTheGlyphsInsteadOfFillingTheCanvas(width: Double) async throws {
        let red = Color(red: 1, green: 0, blue: 0)
        let raster = try await rasterize(Hokusai.text("Hi", style: TextStyle(fontSize: 40, color: .white, stroke: TextStroke(color: red, width: width))))

        var clear = 0, stroke = 0, glyph = 0
        for y in 0..<raster.height {
            for x in 0..<raster.width {
                let p = raster.pixel(x, y)
                if p[3] < 40 { clear += 1 }
                if p[3] > 200, p[0] > 200, p[1] < 60, p[2] < 60 { stroke += 1 }
                if p[3] > 200, p[0] > 200, p[1] > 200, p[2] > 200 { glyph += 1 }
            }
        }
        #expect(clear > raster.width * raster.height / 20, "canvas around the letters must stay clear, not become stroke colour")
        #expect(stroke > 0 && glyph > 0, "both the outline and the glyph colour must be present")
    }

    @Test func shadowExtendsTheCanvasTowardsItsOffset() async throws {
        let plain = try await text("Hi", style: TextStyle(fontSize: 40))
        let shadowed = try await text("Hi", style: TextStyle(fontSize: 40, shadow: TextShadow(offsetX: 10, offsetY: 10, blur: 0)))
        #expect(shadowed.width >= plain.width + 10 && shadowed.height >= plain.height + 10)
    }

    @Test func aShadowIsTranslucentInItsOwnColour() async throws {
        // Invisible text over an opaque blue shadow: the ink that remains is the shadow.
        let style = TextStyle(
            fontSize: 40, color: Color(red: 1, green: 1, blue: 1, opacity: 0),
            shadow: TextShadow(offsetX: 0, offsetY: 0, blur: 0, color: Color(red: 0, green: 0, blue: 1, opacity: 1)))
        let peak = strongestPixel(try await rasterize(Hokusai.text("MM", style: style)))
        #expect(peak[3] > 200 && peak[2] > 200 && peak[0] < 60)
    }

    @Test func rotationSwapsTheDimensionsForAQuarterTurn() async throws {
        let upright = try await text("Hello there", style: TextStyle(fontSize: 30))
        let turned = try await text("Hello there", style: TextStyle(fontSize: 30, rotation: 90))
        #expect(turned.width == upright.height && turned.height == upright.width)
    }

    // MARK: - Fonts

    @Test func aMissingFontFileIsATypedReadError() async throws {
        let pipeline = try Hokusai.text("x", style: TextStyle(fontFile: URL(fileURLWithPath: "/nonexistent/Font.ttf")))
        do {
            _ = try await pipeline.metadata()
            Issue.record("expected an io error")
        } catch HokusaiError.io(_, let operation, _) {
            #expect(operation == .read)
        }
    }

    // MARK: - Validation

    @Test func invalidOptionsFailWhenTheSourceIsBuilt() {
        let cases: [(String, () throws -> Hokusai)] = [
            ("text", { try Hokusai.text("") }),
            ("font", { try Hokusai.text("x", style: TextStyle(font: " ")) }),
            ("font", { try Hokusai.text("x", style: TextStyle(font: "/fonts/a.ttf")) }),
            ("fontSize", { try Hokusai.text("x", style: TextStyle(fontSize: 0)) }),
            ("dpi", { try Hokusai.text("x", style: TextStyle(dpi: 0)) }),
            ("lineHeight", { try Hokusai.text("x", style: TextStyle(lineHeight: .nan)) }),
            ("lineHeight", { try Hokusai.text("x", style: TextStyle(lineHeight: 9)) }),
            ("rotation", { try Hokusai.text("x", style: TextStyle(rotation: .infinity)) }),
            ("width", { try Hokusai.text("x", layout: .width(0)) }),
            ("fit", { try Hokusai.text("x", layout: .fit(width: 100, height: 0)) }),
            ("lineHeight", { try Hokusai.text("x", layout: .fit(width: 100, height: 50), style: TextStyle(lineHeight: 1.5)) }),
            ("stroke.width", { try Hokusai.text("x", style: TextStyle(stroke: TextStroke(color: .white, width: 0))) }),
            ("stroke.width", { try Hokusai.text("x", style: TextStyle(stroke: TextStroke(color: .white, width: 65))) }),
            ("shadow.offset", { try Hokusai.text("x", style: TextStyle(shadow: TextShadow(offsetX: Int.min, offsetY: 0))) }),
            ("fontFile", { try Hokusai.text("x", style: TextStyle(fontFile: URL(string: "https://example.com/a.ttf"))) }),
        ]
        for (field, make) in cases {
            do {
                _ = try make()
                Issue.record("\(field) was not rejected")
            } catch HokusaiError.invalidOption(let name, _) {
                #expect(name == field)
            } catch {
                Issue.record("\(field): expected invalidOption, got \(error)")
            }
        }
    }

    // MARK: - Drawing on an image

    private func white(_ width: Int, _ height: Int) throws -> Hokusai {
        try Raster.solid(width: width, height: height, [255, 255, 255, 255]).pipeline()
    }

    @Test func drawTextCompositesAtAGravityPlacement() async throws {
        let raster = try await rasterize(white(200, 100)
            .drawText("Hi", placement: .gravity(.southEast, offsetX: 10, offsetY: 10), style: TextStyle(fontSize: 24)))
        #expect((raster.width, raster.height) == (200, 100))
        #expect(raster.pixel(0, 0) == [255, 255, 255, 255], "far from the text nothing changes")
        var inked = false
        for y in 50..<100 { for x in 140..<200 where raster.pixel(x, y)[0] < 200 { inked = true } }
        #expect(inked, "the text lands in the south-east quadrant")
    }

    @Test func drawTextIsTheSameAsCompositingATextSource() async throws {
        let style = TextStyle(fontSize: 24)
        let placement = Placement.at(x: 5, y: 7)
        let base = try white(120, 60)
        let sugar = try await rasterize(base.drawText("Hi", placement: placement, style: style))
        let layered = try await rasterize(base.composite([CompositeLayer(Hokusai.text("Hi", style: style), placement: placement)]))
        expectPixels(sugar, match: layered)
    }

    @Test func textPartlyOutsideTheImageIsClipped() async throws {
        let raster = try await rasterize(white(40, 20).drawText("Wide text here", placement: .at(x: -30, y: 5), style: TextStyle(fontSize: 20)))
        #expect((raster.width, raster.height) == (40, 20))
    }

    @Test func oneTextSourceCanBeReusedAcrossConcurrentBranches() async throws {
        let label = try Hokusai.text("Hi", style: TextStyle(fontSize: 20))
        let bases = try (1...5).map { try white(40 * $0, 40) }
        let widths = try await withThrowingTaskGroup(of: Int.self) { group in
            for base in bases {
                group.addTask { try await base.composite([CompositeLayer(label, placement: .gravity(.center))]).png().data().info.width }
            }
            return try await group.reduce(into: [Int]()) { $0.append($1) }.sorted()
        }
        #expect(widths == [40, 80, 120, 160, 200])
    }
}
