import Foundation
import Hokusai
import Testing

/// Pixel, tone and alpha effects (#37), black box. Inputs are rasters with
/// stated pixel values and outputs are decoded pixels, so expectations are
/// arithmetic. Tolerances are one or two levels where 8-bit rounding applies.
@Suite struct EffectsSemanticsTests {
    /// A one-row image from RGBA pixels.
    private func row(_ pixels: [[UInt8]]) throws -> Hokusai {
        try Raster(width: pixels.count, height: 1) { x, _ in pixels[x] }.pipeline()
    }

    private func one(_ pixel: [UInt8]) throws -> Hokusai { try row([pixel]) }

    /// A one-row greyscale-valued image.
    private func greys(_ levels: [UInt8]) throws -> Hokusai {
        try row(levels.map { [$0, $0, $0, 255] })
    }

    private func levels(_ pipeline: Hokusai) async throws -> [Int] {
        let raster = try await rasterize(pipeline)
        return (0..<raster.width).map { Int(raster.pixel($0, 0)[0]) }
    }

    private func pixel(_ pipeline: Hokusai, _ x: Int = 0) async throws -> [Int] {
        try await rasterize(pipeline).pixel(x, 0).map { Int($0) }
    }

    private func near(_ actual: [Int], _ expected: [Int], within tolerance: Int = 1) -> Bool {
        actual.count == expected.count && zip(actual, expected).allSatisfy { abs($0 - $1) <= tolerance }
    }

    private func expectInvalidOption(
        _ body: () throws -> Hokusai, _ label: String, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        do {
            _ = try body()
            Issue.record("expected \(label) to be rejected", sourceLocation: sourceLocation)
        } catch HokusaiError.invalidOption {
        } catch {
            Issue.record("\(label): expected invalidOption, got \(error)", sourceLocation: sourceLocation)
        }
    }

    // MARK: - Order

    @Test func effectsRunInTheWrittenOrder() async throws {
        let source = try one([100, 100, 100, 255])
        let gammaThenNegate = try await pixel(source.gamma(2).negate())
        let negateThenGamma = try await pixel(source.negate().gamma(2))
        #expect(gammaThenNegate != negateThenGamma)
        // gamma 2: 255 * (100/255)^(1/2) = 160, then 255 - 160.
        #expect(near(Array(gammaThenNegate.prefix(3)), [95, 95, 95]))
    }

    @Test func effectsAfterAResizeSeeTheResizedPixels() async throws {
        let result = try await rasterize(row([[0, 0, 0, 255], [255, 255, 255, 255]]).resize(width: 1, height: 1, fit: .fill).negate())
        #expect((result.width, result.height) == (1, 1))
    }

    // MARK: - Blur

    @Test func blurSpreadsAPointAndALargerSigmaSpreadsFurther() async throws {
        let source = try greys([0, 0, 0, 0, 255, 0, 0, 0, 0])
        let narrow = try await levels(source.blur(sigma: 0.7))
        let wide = try await levels(source.blur(sigma: 2.5))
        #expect(narrow[4] < 255 && narrow[3] > 0)
        #expect(wide[2] > narrow[2], "a wider sigma reaches further")
        let byDefault = try await levels(source.blur())
        let explicit = try await levels(source.blur(sigma: 1))
        #expect(byDefault == explicit, "the default is sigma 1")
    }

    @Test(arguments: BlurPrecision.allCases)
    func everyPrecisionBlurs(precision: BlurPrecision) async throws {
        let values = try await levels(greys([0, 0, 255, 0, 0]).blur(sigma: 1, precision: precision))
        #expect(values[2] < 255 && values[1] > 0)
    }

    @Test func blurRejectsBadParameters() throws {
        let source = try one([1, 2, 3, 255])
        for sigma in [0, -1, Double.nan, .infinity] {
            expectInvalidOption({ try source.blur(sigma: sigma) }, "sigma \(sigma)")
        }
        for amplitude in [0, -0.1, Double.nan, 11] {
            expectInvalidOption({ try source.blur(sigma: 1, minAmplitude: amplitude) }, "minAmplitude \(amplitude)")
        }
    }

    @Test func blurDoesNotBleedTheColourOfTransparentPixels() async throws {
        // White, fully transparent black, white: blurring colour and alpha
        // independently would drag the middle pixel towards black.
        let source = try row([[255, 255, 255, 255], [0, 0, 0, 0], [255, 255, 255, 255]])
        let middle = try await pixel(source.blur(sigma: 1), 1)
        #expect(middle[0] >= 250 && middle[1] >= 250 && middle[2] >= 250, "got \(middle)")
        #expect(middle[3] > 0)
    }

    // MARK: - Sharpen

    @Test func sharpenOvershootsOnTheBrightSideOfAnEdge() async throws {
        let edge = try Raster(width: 8, height: 8) { x, _ in x < 4 ? [60, 60, 60, 255] : [190, 190, 190, 255] }.pipeline()
        let plain = try await rasterize(edge.sharpen())
        let strong = try await rasterize(edge.sharpen(SharpenOptions(sigma: 1, flat: 0, jagged: 8)))
        #expect(plain.pixel(4, 4)[0] > 190, "overshoot past the bright level")
        #expect(strong.pixel(4, 4)[0] >= plain.pixel(4, 4)[0])
    }

    @Test func sharpenKeepsAlphaAndRejectsBadOptions() async throws {
        let source = try row([[10, 10, 10, 77], [240, 240, 240, 77]])
        #expect(try await pixel(source.sharpen())[3] == 77)
        expectInvalidOption({ try source.sharpen(SharpenOptions(sigma: 0)) }, "sigma 0")
        expectInvalidOption({ try source.sharpen(SharpenOptions(jagged: -1)) }, "jagged -1")
        expectInvalidOption({ try source.sharpen(SharpenOptions(maxBrightening: .nan)) }, "maxBrightening nan")
    }

    // MARK: - Grayscale and tint

    @Test func grayscaleKeepsAlphaAndEqualisesTheColourChannels() async throws {
        let result = try await pixel(one([255, 0, 0, 77]).grayscale())
        #expect(result[0] == result[1] && result[1] == result[2], "got \(result)")
        #expect(result[3] == 77)
    }

    @Test func convertingToGrayscaleOutputsOneColourChannelPlusAlpha() async throws {
        let opaque = try await Hokusai(data: one([255, 0, 0, 255]).convert(to: .grayscale).png().data().data).metadata()
        #expect(opaque.pixel.channels <= 2 && opaque.pixel.interpretation == .grayscale)

        let translucent = try await pixel(one([255, 0, 0, 77]).convert(to: .grayscale))
        #expect(translucent[3] == 77)
    }

    @Test func tintKeepsAlphaAndColoursLuminance() async throws {
        let result = try await pixel(one([200, 200, 200, 77]).tint(Color(red: 1, green: 0, blue: 0)))
        #expect(result[0] > 100 && result[1] <= 2 && result[2] <= 2, "should be red, got \(result)")
        #expect(result[3] == 77)
    }

    @Test func tintOfAnOpaqueImageStaysOpaque() async throws {
        let result = try await pixel(one([255, 255, 255, 255]).tint(Color(red: 0.2, green: 0.4, blue: 0.8)))
        #expect(near(result, [51, 102, 204, 255], within: 2))
    }

    // MARK: - Normalize and CLAHE

    @Test func normalizeStretchesBetweenPercentiles() async throws {
        let ramp = try greys((0..<40).map { UInt8(100 + $0) })
        let values = try await levels(ramp.normalize(lower: 0, upper: 100))
        #expect(values[0] == 0 && values[39] == 255)
        #expect((120...140).contains(values[20]), "the midpoint maps near the middle, got \(values[20])")
    }

    @Test func normalizeClipsOutsideThePercentiles() async throws {
        var ramp = (0..<98).map { UInt8(100 + $0 / 4) }
        ramp.insert(0, at: 0)
        ramp.append(255)
        let values = try await levels(greys(ramp).normalize(lower: 2, upper: 98))
        #expect(values[0] == 0 && values[values.count - 1] == 255)
    }

    @Test func normalizeKeepsAlpha() async throws {
        let source = try row([[100, 120, 140, 90], [140, 160, 180, 90]])
        let result = try await rasterize(source.normalize(lower: 0, upper: 100))
        #expect(result.pixel(0, 0)[3] == 90 && result.pixel(1, 0)[3] == 90)
    }

    @Test func aFlatImageIsNotNormalized() async throws {
        #expect(try await levels(greys([120, 120, 120, 120]).normalize()) == [120, 120, 120, 120])
    }

    @Test func normalizeRejectsBadPercentiles() throws {
        let source = try one([1, 2, 3, 255])
        for (lower, upper) in [(50.0, 50.0), (60, 40), (-1, 99), (1, 101), (.nan, 99), (1, .infinity)] {
            expectInvalidOption({ try source.normalize(lower: lower, upper: upper) }, "percentiles \(lower)…\(upper)")
        }
    }

    @Test func claheRaisesLocalContrastOfAFlatRamp() async throws {
        let ramp = (0..<64).map { UInt8(100 + $0 * 39 / 63) }
        let source = try Raster(width: 64, height: 64) { x, _ in [ramp[x], ramp[x], ramp[x], 255] }.pipeline()
        let result = try await rasterize(source.clahe(width: 8, height: 8, maxSlope: 3))
        let row = (0..<64).map { Int(result.pixel($0, 32)[0]) }
        #expect((row.max() ?? 0) - (row.min() ?? 0) > 39, "range exceeds the input range of 39")
    }

    @Test func claheRejectsBadParameters() throws {
        let source = try one([1, 2, 3, 255])
        expectInvalidOption({ try source.clahe(width: 0) }, "width 0")
        expectInvalidOption({ try source.clahe(maxSlope: -1) }, "maxSlope -1")
    }

    // MARK: - Tone

    @Test func gammaBrightensAndLeavesAlphaAlone() async throws {
        let result = try await pixel(one([64, 64, 64, 200]).gamma(2))
        #expect(near(Array(result.prefix(3)), [128, 128, 128], within: 2))
        #expect(result[3] == 200)
    }

    @Test func gammaRejectsBadValues() throws {
        for value in [0, -1, 0.05, 11, Double.nan, .infinity] {
            expectInvalidOption({ try self.one([1, 2, 3, 255]).gamma(value) }, "gamma \(value)")
        }
    }

    @Test func negateInvertsColourAndOnlyInvertsAlphaOnRequest() async throws {
        let source = try one([100, 150, 200, 60])
        #expect(try await pixel(source.negate()) == [155, 105, 55, 60])
        #expect(try await pixel(source.negate(alpha: true)) == [155, 105, 55, 195])
    }

    @Test func medianRemovesIsolatedNoise() async throws {
        let source = try Raster(width: 5, height: 5) { x, y in
            x == 2 && y == 2 ? [255, 255, 255, 255] : [100, 100, 100, 255]
        }.pipeline()
        #expect(try await rasterize(source.median(size: 3)).pixel(2, 2)[0] == 100)
    }

    @Test func medianRejectsBadSizes() throws {
        for size in [0, -3, 102] {
            expectInvalidOption({ try self.one([1, 2, 3, 255]).median(size: size) }, "size \(size)")
        }
    }

    @Test func thresholdMakesABlackAndWhiteMaskByDefault() async throws {
        let result = try await rasterize(row([[100, 100, 100, 255], [200, 200, 200, 255]]).threshold(128))
        #expect(result.pixel(0, 0) == [0, 0, 0, 255] && result.pixel(1, 0) == [255, 255, 255, 255])
    }

    @Test func thresholdPerBandKeepsTheChannels() async throws {
        #expect(try await pixel(one([100, 200, 100, 255]).threshold(128, grayscale: false)) == [0, 255, 0, 255])
    }

    @Test func thresholdKeepsAlpha() async throws {
        let result = try await pixel(one([200, 200, 200, 55]).threshold(128))
        #expect(result[0] == 255 && result[3] == 55)
    }

    @Test func thresholdRejectsBadLevels() throws {
        for level in [-1, 256, Double.nan] {
            expectInvalidOption({ try self.one([1, 2, 3, 255]).threshold(level) }, "level \(level)")
        }
    }

    @Test func modulateAdjustsBrightnessSaturationAndHue() async throws {
        let source = try one([200, 80, 40, 255])
        let unchanged = try await pixel(source.modulate())
        #expect(near(Array(unchanged.prefix(3)), [200, 80, 40], within: 2))

        let dark = try await pixel(source.modulate(brightness: 0))
        #expect(dark[0] <= 80 && dark[1] <= 5 && dark[2] <= 5, "got \(dark)")

        let flat = try await pixel(source.modulate(saturation: 0))
        #expect(abs(flat[0] - flat[1]) <= 2 && abs(flat[1] - flat[2]) <= 2, "no colour is left, got \(flat)")

        let turned = try await pixel(source.modulate(hue: 180))
        #expect(!near(Array(turned.prefix(3)), Array(unchanged.prefix(3)), within: 20))
    }

    @Test func modulateKeepsAlpha() async throws {
        #expect(try await pixel(one([200, 80, 40, 66]).modulate(brightness: 1.2, saturation: 0.8, hue: 30))[3] == 66)
    }

    @Test func modulateRejectsBadValues() throws {
        let source = try one([1, 2, 3, 255])
        expectInvalidOption({ try source.modulate(brightness: -1) }, "brightness -1")
        expectInvalidOption({ try source.modulate(saturation: .nan) }, "saturation nan")
        expectInvalidOption({ try source.modulate(hue: .infinity) }, "hue infinity")
    }

    // MARK: - Alpha

    @Test func ensureAlphaAddsConstantOpacityOnlyWhenMissing() async throws {
        let rgb = try await Hokusai(data: one([10, 20, 30, 255]).removeAlpha().png().data().data)
        #expect(try await pixel(rgb.ensureAlpha(opacity: 0.5)).last.map { abs($0 - 128) <= 1 } == true)
        #expect(try await pixel(rgb.ensureAlpha()) == [10, 20, 30, 255])

        let translucent = try one([10, 20, 30, 77])
        #expect(try await pixel(translucent.ensureAlpha(opacity: 0.5)) == [10, 20, 30, 77], "an existing alpha is kept")
    }

    @Test func ensureAlphaRejectsBadOpacity() throws {
        for opacity in [-0.1, 1.1, Double.nan] {
            expectInvalidOption({ try self.one([1, 2, 3, 255]).ensureAlpha(opacity: opacity) }, "opacity \(opacity)")
        }
    }

    @Test func removeAlphaDropsTheChannelWhereFlattenComposites() async throws {
        let source = try one([255, 0, 0, 0])
        let dropped = try await Hokusai(data: source.removeAlpha().png().data().data).metadata()
        #expect(!dropped.pixel.hasAlpha)
        #expect(try await pixel(source.removeAlpha()).prefix(3).elementsEqual([255, 0, 0]), "the colour is untouched")
        #expect(try await pixel(source.flatten(background: .white)) == [255, 255, 255, 255], "the transparent pixel becomes the background")
    }

    @Test func removeAlphaAndFlattenDoNothingToAnOpaqueImage() async throws {
        let rgb = try await Hokusai(data: one([1, 2, 3, 255]).removeAlpha().png().data().data)
        #expect(try await pixel(rgb.removeAlpha()) == [1, 2, 3, 255])
        #expect(try await pixel(rgb.flatten(background: .white)) == [1, 2, 3, 255])
    }

    // MARK: - Concurrency

    @Test func effectHeavyBranchesEvaluateConcurrently() async throws {
        let base = try Hokusai(data: fixtureData(named: "landscape-asym", ext: "jpg")).resize(width: 120)
        async let a = base.grayscale().blur().sharpen().png().data()
        async let b = base.normalize().clahe().gamma().png().data()
        async let c = base.tint(Color(red: 0.8, green: 0.6, blue: 0.4)).modulate(brightness: 1.1).negate().png().data()
        async let d = base.ensureAlpha(opacity: 0.5).median().threshold().png().data()
        let results = try await [a, b, c, d]
        #expect(results.allSatisfy { $0.info.width == 120 && !$0.data.isEmpty })
    }
}
