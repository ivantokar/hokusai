import Foundation
import Testing
@testable import Hokusai

/// Text as a generated pipeline source (#38).
///
/// Following #50, these tests assert layout, escaping, wrapping and graph
/// shape rather than glyph pixels, which differ between fonts and platforms.
@Suite struct TextTests {
    init() throws { try Hokusai.initialize() }

    private func render(_ pipeline: Hokusai, trace: PlanTrace? = nil) throws -> NativeImage {
        try Evaluator.lower(pipeline.plan, context: EvaluationContext(trace: trace))
    }

    private func size(_ pipeline: Hokusai) throws -> (width: Int, height: Int) {
        let image = try render(pipeline)
        return (image.width, image.height)
    }

    private func text(_ content: TextContent, layout: TextLayout = .natural, style: TextStyle = TextStyle()) throws -> Hokusai {
        try Hokusai.text(content, layout: layout, style: style)
    }

    /// The first and last column that has any ink in rows `rows`.
    private func inkColumns(_ image: NativeImage, rows: Range<Int>) throws -> (first: Int, last: Int)? {
        var first: Int?, last: Int?
        for y in rows {
            for x in 0..<image.width where try image.pixel(x: x, y: y).last! > 32 {
                first = min(first ?? x, x)
                last = max(last ?? x, x)
            }
        }
        if let first, let last { return (first, last) }
        return nil
    }

    // MARK: - Standalone source

    @Test func textIsAnOrdinaryPipelineThatEncodesOnItsOwn() async throws {
        let output = try await text("Hello").png().data()
        #expect(output.info.width > 10 && output.info.height > 5)
        let metadata = try await text("Hello").metadata()
        #expect(metadata.width == output.info.width)
    }

    @Test func textRendersRGBAWithTheRequestedColour() throws {
        let image = try render(text("MM", style: TextStyle(fontSize: 40, color: Color(red: 1, green: 0, blue: 0))))
        #expect(image.bands == 4)
        var strongest = [0.0, 0.0, 0.0, 0.0]
        for y in 0..<image.height {
            for x in 0..<image.width {
                let pixel = try image.pixel(x: x, y: y)
                if pixel[3] > strongest[3] { strongest = pixel }
            }
        }
        #expect(strongest[3] > 200 && strongest[0] > 200 && strongest[1] < 60 && strongest[2] < 60)
    }

    @Test func aTextPipelineCanBeTransformedLikeAnyOther() throws {
        let resized = try size(text("Hello", style: TextStyle(fontSize: 40)).resize(width: 30))
        #expect(resized.width == 30)
    }

    @Test func unicodeTextRenders() throws {
        let rendered = try size(text("Привіт 世界 ✓"))
        #expect(rendered.width > 20 && rendered.height > 5)
    }

    // MARK: - Content

    @Test func plainTextIsEscapedSoMarkupCharactersAreLiteral() throws {
        let literal = try size(text(.plain("<b>x</b> & <")))
        #expect(literal.width > 20)
        // Unbalanced markup characters in plain text are not a markup error.
        let stray = try size(text(.plain("<b>")))
        #expect(stray.width > 5)
    }

    @Test func markupIsInterpretedOnlyWhenAskedFor() throws {
        let plain = try size(text(.plain("<span size=\"300%\">A</span>")))
        let marked = try size(text(.markup("<span size=\"300%\">A</span>")))
        let single = try size(text(.plain("A")))
        #expect(marked.height > single.height)
        #expect(plain.width > marked.width)
    }

    @Test func invalidMarkupIsATypedInputError() throws {
        let broken = try text(.markup("<b>unclosed"))
        #expect(throws: HokusaiError.self) { try render(broken) }
    }

    // MARK: - Layout

    private let sentence: TextContent = "the quick brown fox jumps over the lazy dog"

    @Test func widthWrapsWordsWithinTheWidth() throws {
        let style = TextStyle(fontSize: 20)
        let one = try size(text("the", style: style))
        let wrapped = try size(text(sentence, layout: .width(120), style: style))
        #expect(wrapped.width <= 120)
        #expect(wrapped.height > one.height * 2)
    }

    @Test func noWrapKeepsASingleLineAtTheWidth() throws {
        let style = TextStyle(fontSize: 20)
        let natural = try size(text(sentence, style: style))
        let unwrapped = try size(text(sentence, layout: .width(120, wrap: .none), style: style))
        #expect(unwrapped.height == natural.height)
    }

    @Test func characterWrapBreaksALongWordThatWordWrapKeeps() throws {
        let long: TextContent = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"
        let style = TextStyle(fontSize: 20)
        let one = try size(text(long, style: style))
        let byWord = try size(text(long, layout: .width(100, wrap: .word), style: style))
        let byCharacter = try size(text(long, layout: .width(100, wrap: .character), style: style))
        let both = try size(text(long, layout: .width(100, wrap: .wordCharacter), style: style))
        #expect(byWord.height == one.height)
        #expect(byCharacter.height > one.height)
        #expect(both.height > one.height)
    }

    @Test func fitChoosesAResolutionThatFillsTheBox() throws {
        let fitted = try size(text("Fit me", layout: .fit(width: 300, height: 100)))
        #expect(fitted.width <= 300 && fitted.height <= 100)
        #expect(fitted.width > 100 || fitted.height > 50)
    }

    @Test func fitIgnoresTheStyleDPI() throws {
        let low = try size(text("Fit me", layout: .fit(width: 200, height: 80), style: TextStyle(dpi: 72)))
        let high = try size(text("Fit me", layout: .fit(width: 200, height: 80), style: TextStyle(dpi: 600)))
        #expect(low == high)
    }

    @Test func widthOnlyLayoutStillUsesTheFixedDPI() throws {
        let small = try size(text("Hello", layout: .width(2000), style: TextStyle(dpi: 72)))
        let large = try size(text("Hello", layout: .width(2000), style: TextStyle(dpi: 144)))
        #expect(large.height > small.height)
    }

    @Test func lineHeightIsAMultipleOfTheNaturalPitch() throws {
        let style = { (m: Double) in TextStyle(fontSize: 30, lineHeight: m) }
        let two: TextContent = "Ag\nAg"
        let one = try size(text("Ag", style: style(1)))
        let normal = try size(text(two, style: style(1)))
        let double = try size(text(two, style: style(2)))
        let tight = try size(text(two, style: style(0.5)))
        let pitch = normal.height - one.height
        #expect(abs((double.height - normal.height) - pitch) <= 2)
        #expect(abs((normal.height - tight.height) - pitch / 2) <= 2)
    }

    @Test func alignmentMovesShortLinesWithinTheBox() throws {
        let content: TextContent = "i\nWWWWWWWW"
        func columns(_ alignment: TextAlignment) throws -> (first: Int, last: Int)? {
            let image = try render(text(content, style: TextStyle(fontSize: 30, alignment: alignment)))
            return try inkColumns(image, rows: 0..<(image.height / 3))
        }
        let leftColumns = try columns(.left), centreColumns = try columns(.center), rightColumns = try columns(.right)
        let left = try #require(leftColumns)
        let centre = try #require(centreColumns)
        let right = try #require(rightColumns)
        #expect(left.first < centre.first && centre.first < right.first)
    }

    @Test func justifyStretchesWrappedLinesToTheWidth() throws {
        let style = { (justify: Bool) in TextStyle(fontSize: 18, justify: justify) }
        func firstLineEnd(_ justify: Bool) throws -> Int {
            let image = try render(text(sentence, layout: .width(160), style: style(justify)))
            let columns = try inkColumns(image, rows: 0..<14)
            return try #require(columns).last
        }
        let ragged = try firstLineEnd(false)
        let justified = try firstLineEnd(true)
        #expect(justified >= ragged)
        #expect(justified >= 150)
    }

    // MARK: - Stroke, shadow, rotation

    @Test func strokeGrowsTheCanvasByItsRadiusOnEverySide() throws {
        let plain = try size(text("Hi", style: TextStyle(fontSize: 40)))
        let stroked = try size(text("Hi", style: TextStyle(fontSize: 40, stroke: TextStroke(color: .white, width: 4))))
        #expect(stroked.width == plain.width + 8 && stroked.height == plain.height + 8)
    }

    @Test func strokeThicknessDoesNotGrowTheGraph() throws {
        func layers(_ width: Double) throws -> [PlanTrace.Event] {
            let trace = PlanTrace()
            _ = try render(text("Hi", style: TextStyle(fontSize: 40, stroke: TextStroke(color: .white, width: width))), trace: trace)
            return trace.events.filter { if case .compositeBlended = $0 { true } else { false } }
        }
        let thin = try layers(1)
        let thick = try layers(30)
        #expect(thin == [.compositeBlended(layers: 2)])
        #expect(thick == thin)
    }

    @Test func shadowAndStrokeTogetherUseOneBoundedComposite() throws {
        let trace = PlanTrace()
        let style = TextStyle(fontSize: 40, stroke: TextStroke(color: .white, width: 3), shadow: TextShadow(offsetX: 4, offsetY: 4))
        _ = try render(text("Hi", style: style), trace: trace)
        let blends = trace.events.filter { if case .compositeBlended = $0 { true } else { false } }
        #expect(blends == [.compositeBlended(layers: 3)])
    }

    @Test func shadowExtendsTheCanvasTowardsItsOffset() throws {
        let plain = try size(text("Hi", style: TextStyle(fontSize: 40)))
        let shadowed = try size(text("Hi", style: TextStyle(fontSize: 40, shadow: TextShadow(offsetX: 10, offsetY: 10, blur: 0))))
        #expect(shadowed.width >= plain.width + 10 && shadowed.height >= plain.height + 10)
    }

    @Test func aShadowLayerIsTranslucentInItsOwnColour() throws {
        let style = TextStyle(
            fontSize: 40, color: Color(red: 1, green: 1, blue: 1, opacity: 0),
            shadow: TextShadow(offsetX: 0, offsetY: 0, blur: 0, color: Color(red: 0, green: 0, blue: 1, opacity: 1)))
        let image = try render(text("MM", style: style))
        var peak = [0.0, 0.0, 0.0, 0.0]
        for y in 0..<image.height {
            for x in 0..<image.width {
                let pixel = try image.pixel(x: x, y: y)
                if pixel[3] > peak[3] { peak = pixel }
            }
        }
        #expect(peak[3] > 200 && peak[2] > 200 && peak[0] < 60)
    }

    @Test func rotationReusesTheGeometryTransform() throws {
        let upright = try size(text("Hello there", style: TextStyle(fontSize: 30)))
        let turned = try size(text("Hello there", style: TextStyle(fontSize: 30, rotation: 90)))
        #expect(turned.width == upright.height && turned.height == upright.width)
    }

    // MARK: - Fonts

    @Test func aMissingFontFileIsATypedReadError() throws {
        let missing = URL(fileURLWithPath: "/nonexistent/Font.ttf")
        let pipeline = try text("x", style: TextStyle(fontFile: missing))
        let error = #expect(throws: HokusaiError.self) { try render(pipeline) }
        guard case .io(_, let operation, _)? = error else {
            Issue.record("expected an io error, got \(String(describing: error))")
            return
        }
        #expect(operation == .read)
    }

    @Test func aFontFileRendersWhenTheBuildSupportsIt() throws {
        let candidates = [
            "/System/Library/Fonts/Supplemental/Verdana Bold.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        ]
        guard let path = candidates.first(where: { FileManager.default.isReadableFile(atPath: $0) }) else { return }
        let pipeline = try text("File font", style: TextStyle(fontFile: URL(fileURLWithPath: path)))
        let rendered = try size(pipeline)
        #expect(rendered.width > 20)
    }

    // MARK: - Validation

    @Test func invalidOptionsFailWhenTheSourceIsBuilt() throws {
        let cases: [() throws -> Hokusai] = [
            { try Hokusai.text("") },
            { try Hokusai.text("x", style: TextStyle(font: " ")) },
            { try Hokusai.text("x", style: TextStyle(font: "/fonts/a.ttf")) },
            { try Hokusai.text("x", style: TextStyle(fontSize: 0)) },
            { try Hokusai.text("x", style: TextStyle(dpi: 0)) },
            { try Hokusai.text("x", style: TextStyle(lineHeight: .nan)) },
            { try Hokusai.text("x", style: TextStyle(lineHeight: 9)) },
            { try Hokusai.text("x", style: TextStyle(rotation: .infinity)) },
            { try Hokusai.text("x", layout: .width(0)) },
            { try Hokusai.text("x", layout: .fit(width: 100, height: 0)) },
            { try Hokusai.text("x", layout: .fit(width: 100, height: 50), style: TextStyle(lineHeight: 1.5)) },
            { try Hokusai.text("x", style: TextStyle(stroke: TextStroke(color: .white, width: 0))) },
            { try Hokusai.text("x", style: TextStyle(stroke: TextStroke(color: .white, width: 65))) },
            { try Hokusai.text("x", style: TextStyle(shadow: TextShadow(offsetX: Int.min, offsetY: 0))) },
            { try Hokusai.text("x", style: TextStyle(color: Color(red: 2, green: 0, blue: 0))) },
            { try Hokusai.text("x", style: TextStyle(fontFile: URL(string: "https://example.com/a.ttf"))) },
        ]
        for (index, make) in cases.enumerated() {
            do {
                _ = try make()
                Issue.record("case \(index) did not throw")
            } catch is HokusaiError {
            }
        }
    }

    // MARK: - Drawing on an image

    private func white(_ width: Int, _ height: Int) throws -> Hokusai {
        try Hokusai(data: makePNG(width: width, height: height, bands: 4, pixels: [UInt8](repeating: 255, count: width * height * 4)))
    }

    @Test func drawTextCompositesAtAGravityPlacement() throws {
        let style = TextStyle(fontSize: 24)
        let image = try render(white(200, 100).drawText("Hi", placement: .gravity(.southEast, offsetX: 10, offsetY: 10), style: style))
        #expect(image.width == 200 && image.height == 100)
        let corner = try image.pixel(x: 0, y: 0)
        #expect(corner.prefix(3).allSatisfy { $0 == 255 })
        var inked = false
        for y in 50..<100 { for x in 140..<200 where try image.pixel(x: x, y: y)[0] < 200 { inked = true } }
        #expect(inked)
    }

    @Test func drawTextIsTheSameAsCompositingATextSource() throws {
        let style = TextStyle(fontSize: 24)
        let placement = Placement.at(x: 5, y: 7)
        let base = try white(120, 60)
        let sugar = try render(base.drawText("Hi", placement: placement, style: style))
        let layered = try render(base.composite([CompositeLayer(text("Hi", style: style), placement: placement)]))
        var identical = true
        for y in stride(from: 0, to: 60, by: 3) {
            for x in stride(from: 0, to: 120, by: 3) where try sugar.pixel(x: x, y: y) != layered.pixel(x: x, y: y) { identical = false }
        }
        #expect(identical)
    }

    @Test func textPartlyOutsideTheImageIsClipped() throws {
        let image = try render(white(40, 20).drawText("Wide text here", placement: .at(x: -30, y: 5), style: TextStyle(fontSize: 20)))
        #expect(image.width == 40 && image.height == 20)
    }

    @Test func oneTextSourceCanBeReusedAcrossConcurrentBranches() async throws {
        let label = try text("Hi", style: TextStyle(fontSize: 20))
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
