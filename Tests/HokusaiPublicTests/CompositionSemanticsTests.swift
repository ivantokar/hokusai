import Foundation
import Hokusai
import Testing

/// Composition (#25), black box. Inputs are rasters with stated pixel values
/// and outputs are decoded pixels, so every expectation is arithmetic.
@Suite struct CompositionSemanticsTests {
    private static let white: [UInt8] = [255, 255, 255, 255]
    private static let red: [UInt8] = [255, 0, 0, 255]
    private static let blue: [UInt8] = [0, 0, 255, 255]

    private func solid(_ width: Int, _ height: Int, _ colour: [UInt8]) throws -> Hokusai {
        try Raster.solid(width: width, height: height, colour).pipeline()
    }

    private func checker() throws -> Hokusai {
        let tile = Raster(width: 2, height: 2) { x, y in (x + y) % 2 == 0 ? Self.red : Self.blue }
        return try tile.pipeline()
    }

    private func rgb(_ raster: Raster, _ x: Int, _ y: Int) -> [Int] {
        raster.pixel(x, y).prefix(3).map { Int($0) }
    }

    private func close(_ actual: [Int], _ expected: [Int], within delta: Int = 2) -> Bool {
        zip(actual, expected).allSatisfy { abs($0 - $1) <= delta }
    }

    /// Composites one 1×1 layer over a 1×1 base and reads the result.
    private func blend(_ mode: BlendMode, base: [UInt8], layer: [UInt8]) async throws -> Raster {
        let top = try solid(1, 1, layer)
        return try await rasterize(solid(1, 1, base).composite([CompositeLayer(top, blend: mode)]))
    }

    // MARK: - Placement

    @Test func exactPlacementPutsTheTopLeftCornerThere() async throws {
        let result = try await rasterize(solid(4, 4, Self.white)
            .composite([CompositeLayer(solid(2, 2, Self.red), placement: .at(x: 1, y: 1))]))
        for (x, y, expected) in [(1, 1, [255, 0, 0]), (2, 2, [255, 0, 0]), (0, 0, [255, 255, 255]), (3, 3, [255, 255, 255])] {
            #expect(rgb(result, x, y) == expected, "pixel \(x),\(y)")
        }
    }

    @Test func negativeAndOutOfBoundsPositionsAreClippedNotRejected() async throws {
        let base = try solid(4, 4, Self.white)
        let partly = try await rasterize(base.composite([CompositeLayer(solid(3, 3, Self.red), x: -2, y: -2)]))
        #expect(rgb(partly, 0, 0) == [255, 0, 0] && rgb(partly, 1, 1) == [255, 255, 255])

        let away = try await rasterize(base.composite([CompositeLayer(solid(3, 3, Self.red), x: 100, y: -100)]))
        expectPixels(away, match: Raster.solid(width: 4, height: 4, Self.white))
    }

    @Test func aLayerLargerThanTheBaseIsClippedToIt() async throws {
        let result = try await rasterize(solid(2, 2, Self.white).composite([CompositeLayer(solid(10, 10, Self.red))]))
        expectPixels(result, match: Raster.solid(width: 2, height: 2, Self.red))
    }

    @Test func absurdCoordinatesAreRejectedWhenTheLayerIsAdded() throws {
        let base = try solid(2, 2, Self.white)
        let layer = try solid(1, 1, Self.red)
        #expect(throws: HokusaiError.self) { try base.composite([CompositeLayer(layer, x: Int.max)]) }
        #expect(throws: HokusaiError.self) {
            try base.composite([CompositeLayer(layer, placement: .gravity(.center, offsetX: Int.min))])
        }
    }

    // MARK: - Order

    @Test func laterLayersDrawOverEarlierOnes() async throws {
        let base = try solid(2, 2, Self.white)
        let red = try solid(2, 2, Self.red), blue = try solid(2, 2, Self.blue)
        let blueOnTop = try await rasterize(base.composite([CompositeLayer(red), CompositeLayer(blue)]))
        let redOnTop = try await rasterize(base.composite([CompositeLayer(blue), CompositeLayer(red)]))
        #expect(rgb(blueOnTop, 0, 0) == [0, 0, 255])
        #expect(rgb(redOnTop, 0, 0) == [255, 0, 0])
    }

    @Test func oneCompositeWithManyLayersEqualsSuccessiveComposites() async throws {
        let base = try solid(6, 6, Self.white)
        let a = try CompositeLayer(solid(3, 3, Self.red), x: 0, y: 0, opacity: 0.6)
        let b = try CompositeLayer(solid(3, 3, Self.blue), x: 2, y: 2, opacity: 0.5)

        let together = try await rasterize(base.composite([a, b]))
        let stepwise = try await rasterize(base.composite([a]).composite([b]))
        expectPixels(together, match: stepwise, .absolute(maxChannelDelta: 1))
    }

    // MARK: - Opacity

    @Test func halfOpacityMixesHalfOfTheLayer() async throws {
        let result = try await rasterize(solid(2, 2, Self.white).composite([CompositeLayer(solid(2, 2, Self.red), opacity: 0.5)]))
        #expect(close(rgb(result, 0, 0), [255, 128, 128]))
    }

    @Test func zeroOpacityLeavesTheBaseAndFullOpacityIsTheDefault() async throws {
        let base = try solid(2, 2, Self.white)
        let red = try solid(2, 2, Self.red)
        let none = try await rasterize(base.composite([CompositeLayer(red, opacity: 0)]))
        let explicit = try await rasterize(base.composite([CompositeLayer(red, opacity: 1)]))
        let implicit = try await rasterize(base.composite([CompositeLayer(red)]))
        expectPixels(none, match: Raster.solid(width: 2, height: 2, Self.white))
        expectPixels(explicit, match: implicit)
    }

    @Test(arguments: [-0.1, 1.1, Double.nan, Double.infinity])
    func invalidOpacityIsAnInvalidOptionNamingOpacity(opacity: Double) throws {
        let base = try solid(2, 2, Self.white)
        let layer = try solid(1, 1, Self.red)
        do {
            _ = try base.composite([CompositeLayer(layer, opacity: opacity)])
            Issue.record("expected opacity \(opacity) to be rejected")
        } catch HokusaiError.invalidOption(let name, _) {
            #expect(name == "opacity")
        }
    }

    // MARK: - Blend modes

    @Test func multiplyScreenDifferenceAndAddOnKnownColours() async throws {
        let base: [UInt8] = [200, 100, 50, 255], layer: [UInt8] = [100, 200, 50, 255]
        let expectations: [(BlendMode, [Int])] = [
            (.multiply, [78, 78, 10]), (.screen, [222, 222, 90]), (.difference, [100, 100, 0]),
            (.add, [255, 255, 100]), (.darken, [100, 100, 50]), (.lighten, [200, 200, 50]),
        ]
        for (mode, expected) in expectations {
            let result = try await blend(mode, base: base, layer: layer)
            #expect(close(rgb(result, 0, 0), expected), "\(mode)")
        }
    }

    @Test func porterDuffModesKeepTheRightSide() async throws {
        let source = try await blend(.source, base: Self.white, layer: Self.red)
        let destination = try await blend(.destination, base: Self.white, layer: Self.red)
        let clear = try await blend(.clear, base: Self.white, layer: Self.red)
        #expect(rgb(source, 0, 0) == [255, 0, 0])
        #expect(rgb(destination, 0, 0) == [255, 255, 255])
        #expect(clear.pixel(0, 0)[3] == 0)

        // Over an opaque base, `out`, `destinationOut` and `xor` leave nothing.
        for mode in [BlendMode.out, .destinationOut, .xor] {
            #expect(try await blend(mode, base: Self.white, layer: Self.red).pixel(0, 0)[3] == 0, "\(mode)")
        }
        // `in` keeps the layer where the base is present.
        let layerIn = try await blend(.in, base: Self.white, layer: Self.red)
        #expect(rgb(layerIn, 0, 0) == [255, 0, 0])
    }

    // MARK: - Tiling

    @Test func tilingRepeatsTheLayerOverTheWholeBase() async throws {
        let result = try await rasterize(solid(5, 4, Self.white).composite([CompositeLayer(checker(), placement: .tile())]))
        #expect(result.width == 5 && result.height == 4)
        for y in 0..<4 {
            for x in 0..<5 {
                #expect(rgb(result, x, y) == ((x + y) % 2 == 0 ? [255, 0, 0] : [0, 0, 255]), "pixel \(x),\(y)")
            }
        }
    }

    @Test func tileGravityAlignsOneTileWithThePoint() async throws {
        // Centre of a 5×5 base: the 2×2 tile starts at (1, 1).
        let result = try await rasterize(solid(5, 5, Self.white)
            .composite([CompositeLayer(checker(), placement: .tile(gravity: .center))]))
        #expect(rgb(result, 1, 1) == [255, 0, 0] && rgb(result, 2, 1) == [0, 0, 255])
        #expect(rgb(result, 0, 0) == [255, 0, 0], "the previous tile's last pixel")
    }

    @Test func tilingKeepsOpacityAndBlend() async throws {
        let layer = try CompositeLayer(solid(1, 1, Self.red), placement: .tile(), blend: .over, opacity: 0.5)
        let result = try await rasterize(solid(3, 3, Self.white).composite([layer]))
        #expect(close(rgb(result, 2, 2), [255, 128, 128]))
    }

    @Test func aTileCountBeyondTheLimitIsRejectedWhenEvaluated() async throws {
        let pipeline = try solid(4000, 4000, Self.white)
            .composite([CompositeLayer(solid(1, 1, Self.red), placement: .tile())])
            .png()
        do {
            _ = try await pipeline.data()
            Issue.record("expected the tile count to be limited")
        } catch is HokusaiError {
        }
    }

    // MARK: - Colour handling

    @Test func aGreyBaseAndColourLayerNeedNoManualConversion() async throws {
        let grey = try Raster.solid(width: 2, height: 2, [100, 100, 100, 255]).pipeline().grayscale()
        let result = try await rasterize(grey.composite([CompositeLayer(solid(1, 1, Self.red))]))
        #expect((result.width, result.height) == (2, 2))
        #expect(rgb(result, 0, 0) == [255, 0, 0])
    }

    @Test func linearLightBlendsLighterThanSRGBForHalfBlack() async throws {
        let base = try solid(1, 1, Self.white)
        let layer = try CompositeLayer(solid(1, 1, [0, 0, 0, 255]), opacity: 0.5)
        let stored = try await rasterize(base.composite([layer], space: .srgb))
        let linear = try await rasterize(base.composite([layer], space: .linear))
        #expect(abs(rgb(stored, 0, 0)[0] - 128) <= 2)
        #expect(rgb(linear, 0, 0)[0] > 170)
    }

    // MARK: - Layers are pipelines

    @Test func aLayerPipelineIsTransformedButNeverEncoded() async throws {
        let logo = try solid(4, 4, Self.red).resize(width: 2, height: 2, fit: .fill).png()   // encoder on the layer is ignored
        let result = try await rasterize(solid(8, 8, Self.white).composite([CompositeLayer(logo, x: 3, y: 3)]))
        #expect(rgb(result, 3, 3) == [255, 0, 0] && rgb(result, 4, 4) == [255, 0, 0])
        #expect(rgb(result, 2, 2) == [255, 255, 255] && rgb(result, 5, 5) == [255, 255, 255])
    }

    @Test func oneOverlayCanBeReusedAcrossBranchesConcurrently() async throws {
        let overlay = try CompositeLayer(solid(2, 2, Self.red), x: 1, y: 1)
        let base = try solid(4, 4, Self.white)
        let expected = try await rasterize(base.composite([overlay]))

        try await withThrowingTaskGroup(of: Raster.self) { group in
            for _ in 0..<12 { group.addTask { try await rasterize(base.composite([overlay])) } }
            for try await result in group { expectPixels(result, match: expected) }
        }
    }
}
