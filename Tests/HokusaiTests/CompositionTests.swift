import CVips
import Foundation
import Testing
@testable import Hokusai

/// Multi-pipeline composition on the evaluator (#25).
///
/// Images are built from stated pixel values, so expectations are arithmetic.
@Suite struct CompositionTests {
    init() throws { try Hokusai.initialize() }

    private typealias RGBA = [UInt8]
    private static let white: RGBA = [255, 255, 255, 255]
    private static let red: RGBA = [255, 0, 0, 255]
    private static let blue: RGBA = [0, 0, 255, 255]

    private func solid(_ width: Int, _ height: Int, _ colour: RGBA) throws -> Hokusai {
        let pixels = (0..<width * height).flatMap { _ in colour }
        return try Hokusai(data: makePNG(width: width, height: height, bands: 4, pixels: pixels))
    }

    private func lower(_ pipeline: Hokusai, trace: PlanTrace? = nil) throws -> NativeImage {
        try Evaluator.lower(pipeline.plan, context: EvaluationContext(trace: trace))
    }

    private func rgb(_ image: NativeImage, _ x: Int, _ y: Int) throws -> [Int] {
        Array(try image.pixel(x: x, y: y).prefix(3).map { Int($0.rounded()) })
    }

    private func alpha(_ image: NativeImage, _ x: Int, _ y: Int) throws -> Int {
        Int(try image.pixel(x: x, y: y).last!.rounded())
    }

    // MARK: - Placement

    @Test func exactPlacementPutsTheTopLeftCornerThere() throws {
        let base = try solid(4, 4, Self.white)
        let result = try lower(base.composite([CompositeLayer(solid(2, 2, Self.red), placement: .at(x: 1, y: 1))]))
        let inside = try rgb(result, 1, 1)
        let corner = try rgb(result, 2, 2)
        let outside = try rgb(result, 0, 0)
        let far = try rgb(result, 3, 3)
        #expect(inside == [255, 0, 0] && corner == [255, 0, 0])
        #expect(outside == [255, 255, 255] && far == [255, 255, 255])
    }

    @Test(arguments: [
        (Gravity.northWest, 0, 0), (.north, 4, 0), (.northEast, 8, 0),
        (.west, 0, 4), (.center, 4, 4), (.east, 8, 4),
        (.southWest, 0, 8), (.south, 4, 8), (.southEast, 8, 8),
    ])
    func gravityAnchorsEveryCompassPoint(gravity: Gravity, x: Int, y: Int) {
        let origin = Placement.gravity(gravity).origin(layer: (4, 4), base: (12, 12))
        #expect(origin.x == x && origin.y == y)
    }

    @Test func gravityOffsetsAreInwardPaddingAtEdgesAndSignedShiftsWhenCentred() {
        let layer = (width: 4, height: 4), base = (width: 20, height: 20)
        let northWest = Placement.gravity(.northWest, offsetX: 3, offsetY: 2).origin(layer: layer, base: base)
        let southEast = Placement.gravity(.southEast, offsetX: 3, offsetY: 2).origin(layer: layer, base: base)
        let centre = Placement.gravity(.center, offsetX: -3, offsetY: 2).origin(layer: layer, base: base)
        #expect(northWest == (3, 2))
        #expect(southEast == (13, 14))
        #expect(centre == (5, 10))
    }

    @Test func gravityPlacementReachesThePixels() throws {
        let base = try solid(6, 6, Self.white)
        let layer = try CompositeLayer(solid(2, 2, Self.red), placement: .gravity(.southEast, offsetX: 1, offsetY: 1))
        let result = try lower(base.composite([layer]))
        let painted = try rgb(result, 3, 3)
        let padding = try rgb(result, 5, 5)
        #expect(painted == [255, 0, 0] && padding == [255, 255, 255])
    }

    @Test func negativeAndOutOfBoundsPositionsAreClippedNotRejected() throws {
        let base = try solid(4, 4, Self.white)
        let partly = try lower(base.composite([CompositeLayer(solid(3, 3, Self.red), x: -2, y: -2)]))
        let kept = try rgb(partly, 0, 0)
        let clipped = try rgb(partly, 1, 1)
        #expect(kept == [255, 0, 0] && clipped == [255, 255, 255])

        let away = try lower(base.composite([CompositeLayer(solid(3, 3, Self.red), x: 100, y: -100)]))
        let untouched = try rgb(away, 0, 0)
        #expect(untouched == [255, 255, 255])
        #expect(away.width == 4 && away.height == 4)
    }

    @Test func aLayerLargerThanTheBaseIsClippedToIt() throws {
        let result = try lower(solid(2, 2, Self.white).composite([CompositeLayer(solid(10, 10, Self.red))]))
        #expect(result.width == 2 && result.height == 2)
    }

    @Test func absurdCoordinatesAreRejectedWhenTheLayerIsAdded() throws {
        let base = try solid(2, 2, Self.white)
        let layer = try solid(1, 1, Self.red)
        #expect(throws: HokusaiError.self) { try base.composite([CompositeLayer(layer, x: Int.max)]) }
        #expect(throws: HokusaiError.self) {
            try base.composite([CompositeLayer(layer, placement: .gravity(.center, offsetX: Int.min))])
        }
    }

    // MARK: - Order and the single native call

    @Test func laterLayersDrawOverEarlierOnes() throws {
        let base = try solid(2, 2, Self.white)
        let red = try solid(2, 2, Self.red), blue = try solid(2, 2, Self.blue)
        let blueOnTop = try rgb(lower(base.composite([CompositeLayer(red), CompositeLayer(blue)])), 0, 0)
        let redOnTop = try rgb(lower(base.composite([CompositeLayer(blue), CompositeLayer(red)])), 0, 0)
        #expect(blueOnTop == [0, 0, 255])
        #expect(redOnTop == [255, 0, 0])
    }

    @Test func manyLayersUseOneNativeComposite() throws {
        let base = try solid(8, 8, Self.white)
        let layers = try (0..<5).map { CompositeLayer(try solid(2, 2, Self.red), x: $0, y: $0, opacity: 0.5) }
        let trace = PlanTrace()
        _ = try lower(base.composite(layers), trace: trace)
        let blends = trace.events.filter { if case .compositeBlended = $0 { true } else { false } }
        #expect(blends == [.compositeBlended(layers: 5)])
    }

    @Test func eachCompositeStepIsItsOwnNativeCall() throws {
        let base = try solid(4, 4, Self.white)
        let layer = try solid(1, 1, Self.red)
        let trace = PlanTrace()
        _ = try lower(base.composite([CompositeLayer(layer)]).blur().composite([CompositeLayer(layer), CompositeLayer(layer)]), trace: trace)
        let blends = trace.events.filter { if case .compositeBlended = $0 { true } else { false } }
        #expect(blends == [.compositeBlended(layers: 1), .compositeBlended(layers: 2)])
    }

    // MARK: - Opacity

    @Test func halfOpacityMixesHalfOfTheLayer() throws {
        let result = try lower(solid(2, 2, Self.white).composite([CompositeLayer(solid(2, 2, Self.red), opacity: 0.5)]))
        let mixed = try rgb(result, 0, 0)
        #expect(abs(mixed[0] - 255) <= 1 && abs(mixed[1] - 128) <= 2 && abs(mixed[2] - 128) <= 2)
    }

    @Test func zeroOpacityLeavesTheBaseAndFullOpacityIsTheDefault() throws {
        let base = try solid(2, 2, Self.white)
        let red = try solid(2, 2, Self.red)
        let none = try rgb(lower(base.composite([CompositeLayer(red, opacity: 0)])), 0, 0)
        let explicit = try rgb(lower(base.composite([CompositeLayer(red, opacity: 1)])), 0, 0)
        let implicit = try rgb(lower(base.composite([CompositeLayer(red)])), 0, 0)
        #expect(none == [255, 255, 255])
        #expect(explicit == implicit)
    }

    @Test func opacityKeepsTheLayersFormatAndColour() throws {
        let layer = try lower(solid(1, 1, [200, 100, 50, 255]))
        let sixteen = try layer.applying("cast") { swift_vips_cast($0, $1, Int32(VIPS_FORMAT_USHORT.rawValue)) }
        let faded = try sixteen.scalingAlpha(by: 0.5)
        #expect(faded.bandFormat == sixteen.bandFormat)
        #expect(faded.bands == 4)
        let colour = try rgb(faded, 0, 0)
        let fadedAlpha = try alpha(faded, 0, 0)
        #expect(colour == [200, 100, 50])
        #expect(abs(fadedAlpha - 128) <= 1)
    }

    @Test func opacityOnALayerWithoutAlphaAddsOne() throws {
        let grey = try Hokusai(data: makePNG(width: 1, height: 1, bands: 1, pixels: [200]))
        let faded = try lower(grey).scalingAlpha(by: 0.25)
        #expect(faded.bands == 2)
        let value = try alpha(faded, 0, 0)
        #expect(abs(value - 64) <= 1)
    }

    @Test func invalidOpacityIsRejected() throws {
        let base = try solid(2, 2, Self.white)
        let layer = try solid(1, 1, Self.red)
        for opacity in [-0.1, 1.1, .nan, .infinity] {
            #expect(throws: HokusaiError.self) { try base.composite([CompositeLayer(layer, opacity: opacity)]) }
        }
    }

    // MARK: - Blend modes

    @Test func everyBlendModeMapsToADistinctNativeMode() {
        let values = BlendMode.allCases.map { $0.vipsRawValue }
        #expect(Set(values).count == BlendMode.allCases.count)
        #expect(BlendMode.allCases.count == 25)
    }

    private func blend(_ mode: BlendMode, base: RGBA, layer: RGBA) throws -> NativeImage {
        try lower(solid(1, 1, base).composite([CompositeLayer(solid(1, 1, layer), blend: mode)]))
    }

    @Test func multiplyScreenDifferenceAndAddOnKnownColours() throws {
        let base: RGBA = [200, 100, 50, 255], layer: RGBA = [100, 200, 50, 255]
        let multiply = try rgb(blend(.multiply, base: base, layer: layer), 0, 0)
        let screen = try rgb(blend(.screen, base: base, layer: layer), 0, 0)
        let difference = try rgb(blend(.difference, base: base, layer: layer), 0, 0)
        let add = try rgb(blend(.add, base: base, layer: layer), 0, 0)
        let darken = try rgb(blend(.darken, base: base, layer: layer), 0, 0)
        let lighten = try rgb(blend(.lighten, base: base, layer: layer), 0, 0)
        #expect(zip(multiply, [78, 78, 10]).allSatisfy { abs($0 - $1) <= 2 })
        #expect(zip(screen, [222, 222, 90]).allSatisfy { abs($0 - $1) <= 2 })
        #expect(zip(difference, [100, 100, 0]).allSatisfy { abs($0 - $1) <= 2 })
        #expect(zip(add, [255, 255, 100]).allSatisfy { abs($0 - $1) <= 2 })
        #expect(zip(darken, [100, 100, 50]).allSatisfy { abs($0 - $1) <= 2 })
        #expect(zip(lighten, [200, 200, 50]).allSatisfy { abs($0 - $1) <= 2 })
    }

    @Test func porterDuffModesKeepTheRightSide() throws {
        let opaqueBase = Self.white, opaqueLayer = Self.red
        let source = try blend(.source, base: opaqueBase, layer: opaqueLayer)
        let destination = try blend(.destination, base: opaqueBase, layer: opaqueLayer)
        let clear = try blend(.clear, base: opaqueBase, layer: opaqueLayer)
        let sourceColour = try rgb(source, 0, 0)
        let destinationColour = try rgb(destination, 0, 0)
        let clearAlpha = try alpha(clear, 0, 0)
        #expect(sourceColour == [255, 0, 0])
        #expect(destinationColour == [255, 255, 255])
        #expect(clearAlpha == 0)

        // `out` keeps the layer only where the base is empty: nothing here.
        let out = try alpha(blend(.out, base: opaqueBase, layer: opaqueLayer), 0, 0)
        let destinationOut = try alpha(blend(.destinationOut, base: opaqueBase, layer: opaqueLayer), 0, 0)
        let xor = try alpha(blend(.xor, base: opaqueBase, layer: opaqueLayer), 0, 0)
        #expect(out == 0 && destinationOut == 0 && xor == 0)
        // `in` keeps the layer where the base is present.
        let layerIn = try rgb(blend(.in, base: opaqueBase, layer: opaqueLayer), 0, 0)
        #expect(layerIn == [255, 0, 0])
    }

    // MARK: - Tiling

    private func checker() throws -> Hokusai {
        let pixels: [UInt8] = Self.red + Self.blue + Self.blue + Self.red
        return try Hokusai(data: makePNG(width: 2, height: 2, bands: 4, pixels: pixels))
    }

    @Test func tilingRepeatsTheLayerOverTheWholeBase() throws {
        let result = try lower(solid(5, 4, Self.white).composite([CompositeLayer(checker(), placement: .tile())]))
        #expect(result.width == 5 && result.height == 4)
        for y in 0..<4 {
            for x in 0..<5 {
                let expected = (x + y) % 2 == 0 ? [255, 0, 0] : [0, 0, 255]
                let actual = try rgb(result, x, y)
                #expect(actual == expected, "pixel \(x),\(y)")
            }
        }
    }

    @Test func tileGravityAlignsOneTileWithThePoint() throws {
        // Centre of a 5×5 base: the 2×2 tile starts at (1, 1), so the pattern
        // is shifted by one pixel and (1, 1) shows the tile's first pixel.
        let result = try lower(solid(5, 5, Self.white).composite([CompositeLayer(checker(), placement: .tile(gravity: .center))]))
        let first = try rgb(result, 1, 1)
        let second = try rgb(result, 2, 1)
        let before = try rgb(result, 0, 0)
        #expect(first == [255, 0, 0] && second == [0, 0, 255])
        #expect(before == [255, 0, 0])  // tile pixel (1, 1) of the previous tile
    }

    @Test func tilingKeepsOpacityAndBlend() throws {
        let layer = try CompositeLayer(solid(1, 1, Self.red), placement: .tile(), blend: .over, opacity: 0.5)
        let result = try lower(solid(3, 3, Self.white).composite([layer]))
        let mixed = try rgb(result, 2, 2)
        #expect(abs(mixed[1] - 128) <= 2)
    }

    @Test func aTileCountBeyondTheLimitIsRejected() throws {
        let base = try solid(4000, 4000, Self.white)
        let layer = try solid(1, 1, Self.red)
        let pipeline = try base.composite([CompositeLayer(layer, placement: .tile())])
        #expect(throws: HokusaiError.self) { try lower(pipeline) }
    }

    // MARK: - Colour and format handling

    @Test func aGreyBaseAndRGBLayerNeedNoManualConversion() throws {
        let grey = try Hokusai(data: makePNG(width: 2, height: 2, bands: 1, pixels: [100, 100, 100, 100]))
        let layer = try Hokusai(data: makePNG(width: 1, height: 1, bands: 3, pixels: [255, 0, 0]))
        let result = try lower(grey.composite([CompositeLayer(layer)]))
        #expect(result.width == 2 && result.height == 2)
        let covered = try rgb(result, 0, 0)
        #expect(covered == [255, 0, 0])
    }

    @Test func linearLightBlendsLighterThanSRGBForHalfBlack() throws {
        let base = try solid(1, 1, Self.white)
        let black = try solid(1, 1, [0, 0, 0, 255])
        let layer = CompositeLayer(black, opacity: 0.5)
        let stored = try rgb(lower(base.composite([layer], space: .srgb)), 0, 0)
        let linearImage = try lower(base.composite([layer], space: .linear))
        let linear = try rgb(linearImage, 0, 0)
        #expect(abs(stored[0] - 128) <= 2)
        #expect(linear[0] > 170)
        // Only the mix differs: the output is still 8-bit sRGB, not float scRGB.
        #expect(linearImage.bandFormat == Int32(VIPS_FORMAT_UCHAR.rawValue))
    }

    // MARK: - Layers are pipelines

    @Test func aLayerPipelineIsTransformedButNeverEncoded() async throws {
        let base = try solid(8, 8, Self.white)
        let logo = try solid(4, 4, Self.red)
        let plain = try await base.composite([CompositeLayer(logo.resize(width: 2), x: 1, y: 1)]).png().data()
        let configured = try await base.composite([CompositeLayer(logo.resize(width: 2).jpeg(quality: 1), x: 1, y: 1)]).png().data()
        #expect(plain.data == configured.data)
    }

    @Test func oneOverlayCanBeReusedAcrossBranchesConcurrently() async throws {
        let logo = try solid(2, 2, Self.red)
        let bases = try (1...6).map { try solid(10 * $0, 10 * $0, Self.white) }
        let sizes = try await withThrowingTaskGroup(of: Int.self) { group in
            for base in bases {
                group.addTask {
                    let out = try await base.composite([CompositeLayer(logo, placement: .gravity(.center))]).png().data()
                    return out.info.width
                }
            }
            return try await group.reduce(into: [Int]()) { $0.append($1) }.sorted()
        }
        #expect(sizes == [10, 20, 30, 40, 50, 60])
    }
}
