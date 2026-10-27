import Foundation
import Testing
@testable import Hokusai

/// Shrink-on-load behind the normal `resize` API (#20).
///
/// The contract under test: for an eligible JPEG the evaluator lets the
/// decoder shrink the source, and the result has exactly the dimensions a
/// normal decode and resize gives, with pixels that agree within codec
/// tolerance. `PlannerOptions.reference` is the forced normal path.
@Suite struct ShrinkOnLoadTests {
    init() throws { try Hokusai.initialize() }

    private func landscape() throws -> Hokusai {
        try Hokusai(data: loadFixtureData(named: "landscape-asym", ext: "jpg"))
    }

    private struct Run {
        let image: NativeImage
        let events: [PlanTrace.Event]
        var shrinkFactors: [Int] { events.compactMap { if case .shrinkOnLoad(let factor) = $0 { factor } else { nil } } }
    }

    private func run(_ pipeline: Hokusai, planner: PlannerOptions = .default) throws -> Run {
        let trace = PlanTrace()
        let image = try Evaluator.lower(pipeline.plan, context: EvaluationContext(planner: planner, trace: trace))
        return Run(image: image, events: trace.events)
    }

    private var forcedNormal: PlannerOptions { PlannerOptions(disabled: [.shrinkOnLoad]) }

    /// Mean absolute difference over every pixel and band, on the 0...255 scale.
    private func meanDifference(_ a: NativeImage, _ b: NativeImage) throws -> Double {
        #expect(a.width == b.width && a.height == b.height)
        var total = 0.0
        var count = 0.0
        for y in 0..<min(a.height, b.height) {
            for x in 0..<min(a.width, b.width) {
                for (p, q) in zip(try a.pixel(x: x, y: y), try b.pixel(x: x, y: y)) {
                    total += abs(p - q)
                    count += 1
                }
            }
        }
        return total / max(count, 1)
    }

    // MARK: - Eligibility

    @Test func aJPEGDataSourceIsShrunkByTheDecoder() throws {
        let result = try run(landscape().resize(width: 30))
        #expect(result.shrinkFactors == [8])
        #expect(result.image.width == 30)
    }

    @Test func aJPEGFileSourceIsShrunkByTheDecoder() throws {
        let url = try fixtureURL(named: "landscape-asym", ext: "jpg")
        let result = try run(Hokusai(url: url).resize(width: 30))
        #expect(result.shrinkFactors == [8])
    }

    @Test func theShrinkNeverLeavesFewerPixelsThanTheResizeNeeds() throws {
        // 320 wide: /8 gives 40, /4 gives 80. A 60 pixel target needs /4.
        #expect(try run(landscape().resize(width: 60)).shrinkFactors == [4])
        // A 41 pixel target is just above what /8 leaves.
        #expect(try run(landscape().resize(width: 41)).shrinkFactors == [4])
        // A target at or above the source size cannot shrink at all.
        #expect(try run(landscape().resize(width: 320)).shrinkFactors.isEmpty)
        #expect(try run(landscape().resize(width: 640)).shrinkFactors.isEmpty)
    }

    @Test func autoOrientMayPrecedeTheResize() throws {
        let source = try Hokusai(data: loadFixtureData(named: "orientation-6", ext: "jpg"))
        let result = try run(source.autoOrient().resize(width: 20))
        #expect(result.shrinkFactors == [4])
        #expect((result.image.width, result.image.height) == (20, 30))
    }

    @Test func otherCodecsFallBackWithoutChangingTheAPI() throws {
        let png = try Hokusai(data: loadFixtureData(named: "rgba-alpha", ext: "png"))
        let result = try run(png.resize(width: 2))
        #expect(result.shrinkFactors.isEmpty)
    }

    @Test(arguments: [
        "blur", "extract", "rotate", "trim",
    ])
    func anOperationBeforeTheResizeKeepsFullResolution(before: String) throws {
        let base = try landscape()
        let leading: Hokusai
        switch before {
        case "blur": leading = try base.blur(sigma: 1)
        case "extract": leading = try base.extract(x: 0, y: 0, width: 300, height: 180)
        case "rotate": leading = try base.rotate(by: 90)
        default: leading = try base.trim()
        }
        #expect(try run(leading.resize(width: 30)).shrinkFactors.isEmpty)
    }

    @Test func onlyTheLeadingResizeDecidesTheShrink() throws {
        // 320 → 160 can shrink by 2; the later resize to 30 cannot reach back.
        #expect(try run(landscape().resize(width: 160).resize(width: 30)).shrinkFactors == [2])
        // A leading resize that needs the full size blocks the whole chain.
        #expect(try run(landscape().resize(width: 200).resize(width: 30)).shrinkFactors.isEmpty)
    }

    @Test func theRuleCanBeDisabled() throws {
        #expect(try run(landscape().resize(width: 30), planner: forcedNormal).shrinkFactors.isEmpty)
        #expect(try run(landscape().resize(width: 30), planner: .reference).shrinkFactors.isEmpty)
    }

    @Test func anExplicitPageDisablesIt() throws {
        let data = try loadFixtureData(named: "landscape-asym", ext: "jpg")
        let source = try Hokusai(data: data, options: InputOptions(page: 0))
        #expect(try run(source.resize(width: 30)).shrinkFactors.isEmpty)
    }

    // MARK: - Equivalence with the normal path

    @Test(arguments: [ResizeFit.cover, .contain, .fill, .inside, .outside])
    func dimensionsMatchTheNormalPathForEveryFit(fit: ResizeFit) throws {
        let pipeline = try landscape().resize(width: 50, height: 40, fit: fit)
        let optimised = try run(pipeline)
        let normal = try run(pipeline, planner: forcedNormal)
        #expect(!optimised.shrinkFactors.isEmpty)
        #expect((optimised.image.width, optimised.image.height) == (normal.image.width, normal.image.height))
    }

    @Test func dimensionsMatchForWidthOnlyAndHeightOnlyTargets() throws {
        for pipeline in try [landscape().resize(width: 37), landscape().resize(height: 23)] {
            let optimised = try run(pipeline)
            let normal = try run(pipeline, planner: forcedNormal)
            #expect(!optimised.shrinkFactors.isEmpty)
            #expect((optimised.image.width, optimised.image.height) == (normal.image.width, normal.image.height))
        }
    }

    @Test func withoutEnlargementUsesTheFullResolutionSize() throws {
        // The target is larger than the source, so the written meaning is
        // "keep 320×200"; shrinking must not turn that into a smaller image.
        let pipeline = try landscape().resize(width: 400, withoutEnlargement: true)
        let result = try run(pipeline)
        #expect(result.shrinkFactors.isEmpty)
        #expect((result.image.width, result.image.height) == (320, 200))
    }

    @Test func orientedDimensionsMatchTheNormalPath() throws {
        let source = try Hokusai(data: loadFixtureData(named: "orientation-6", ext: "jpg"))
        let pipeline = try source.autoOrient().resize(width: 25, height: 25, fit: .cover)
        let optimised = try run(pipeline)
        let normal = try run(pipeline, planner: forcedNormal)
        #expect(!optimised.shrinkFactors.isEmpty)
        #expect((optimised.image.width, optimised.image.height) == (normal.image.width, normal.image.height))
        #expect(try meanDifference(optimised.image, normal.image) < 25)
    }

    @Test func pixelsAgreeWithinCodecTolerance() throws {
        let pipeline = try landscape().resize(width: 40, height: 25, fit: .fill)
        let optimised = try run(pipeline)
        let normal = try run(pipeline, planner: forcedNormal)
        #expect(!optimised.shrinkFactors.isEmpty)
        #expect(try meanDifference(optimised.image, normal.image) < 20)
    }

    @Test func attentionCropStillFindsTheDetailBlock() throws {
        let pipeline = try landscape().resize(width: 40, height: 40, fit: .cover, position: .attention)
        let optimised = try run(pipeline)
        #expect(!optimised.shrinkFactors.isEmpty)
        #expect((optimised.image.width, optimised.image.height) == (40, 40))
    }

    // MARK: - Independence and sharing

    @Test func branchesFromOneSourceStayIndependent() async throws {
        let base = try landscape()
        async let small = base.resize(width: 30).png().data()
        async let blurred = base.blur(sigma: 1).resize(width: 30).png().data()
        async let full = base.png().data()
        let (a, b, c) = try await (small, blurred, full)
        #expect(a.info.width == 30 && b.info.width == 30)
        #expect((c.info.width, c.info.height) == (320, 200))
    }

    @Test func aSharedSourceIsNeverHandedBackShrunk() throws {
        // The base image and a resized layer derived from it share a source
        // node. If the layer's shrunk copy were remembered for the source, the
        // base would come out 40×25 instead of 320×200.
        let base = try landscape()
        let layer = CompositeLayer(try base.resize(width: 30), x: 0, y: 0)
        let composed = try run(base.composite([layer]))
        #expect((composed.image.width, composed.image.height) == (320, 200))
    }

    @Test func aSharedSourceInTheOtherOrderAlsoKeepsFullResolution() throws {
        let base = try landscape()
        let layer = CompositeLayer(try base.resize(width: 30), x: 0, y: 0)
        // Resizing first makes the base itself the shrunk plan; the layer
        // derived from the same source must still see 320×200 when it needs it.
        let outer = try base.resize(width: 100).composite([CompositeLayer(try base.blur(sigma: 1), x: 0, y: 0), layer])
        let composed = try run(outer)
        #expect(composed.image.width == 100)
    }

    // MARK: - Failure behaviour

    @Test func aTruncatedJPEGStillReportsADecodeFailure() async throws {
        let data = try loadFixtureData(named: "truncated", ext: "jpg")
        await #expect(throws: HokusaiError.self) {
            _ = try await Hokusai(data: data).resize(width: 30).png().data()
        }
    }
}
