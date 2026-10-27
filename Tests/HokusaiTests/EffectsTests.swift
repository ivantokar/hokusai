import Foundation
import Testing
@testable import Hokusai

/// Pixel, tone and alpha effects on the evaluator (#37).
///
/// Every image here is built from stated pixel values (`makePNG`), so the
/// expected output is arithmetic rather than a comparison with a fixture.
@Suite struct EffectsTests {
    init() throws { try Hokusai.initialize() }

    private func lower(_ pipeline: Hokusai) throws -> NativeImage {
        try Evaluator.lower(pipeline.plan, context: EvaluationContext())
    }

    private func rgb(_ pixels: [UInt8], width: Int = 1) throws -> Hokusai {
        try Hokusai(data: makePNG(width: width, height: pixels.count / 3 / width, bands: 3, pixels: pixels))
    }

    private func rgba(_ pixels: [UInt8], width: Int = 1) throws -> Hokusai {
        try Hokusai(data: makePNG(width: width, height: pixels.count / 4 / width, bands: 4, pixels: pixels))
    }

    private func grey(_ pixels: [UInt8], width: Int) throws -> Hokusai {
        try Hokusai(data: makePNG(width: width, height: pixels.count / width, bands: 1, pixels: pixels))
    }

    /// Rounds so a test compares what the 8-bit pipeline can actually produce.
    private func values(_ image: NativeImage, x: Int = 0, y: Int = 0) throws -> [Int] {
        try image.pixel(x: x, y: y).map { Int($0.rounded()) }
    }

    private func near(_ actual: [Int], _ expected: [Int], tolerance: Int = 1) -> Bool {
        actual.count == expected.count && zip(actual, expected).allSatisfy { abs($0 - $1) <= tolerance }
    }

    // MARK: - Order

    @Test func effectsRunInTheWrittenOrder() throws {
        let source = try rgb([100, 100, 100])
        let gammaThenNegate = try values(lower(source.gamma(2).negate()))
        let negateThenGamma = try values(lower(source.negate().gamma(2)))
        #expect(gammaThenNegate != negateThenGamma)
        // gamma 2: 255 * (100/255)^(1/2) = 160, then 255 - 160.
        #expect(near(gammaThenNegate, [95, 95, 95]))
    }

    @Test func effectsAfterAResizeSeeTheResizedPixels() throws {
        let source = try rgb([0, 0, 0, 255, 255, 255], width: 2)
        let image = try lower(source.resize(width: 1, height: 1, fit: .fill).negate())
        #expect((image.width, image.height) == (1, 1))
    }

    // MARK: - Blur

    @Test func defaultAndExplicitGaussianBlurAgree() throws {
        let source = try grey([0, 0, 255, 0, 0], width: 5)
        let mild = try values(lower(source.blur()), x: 2)
        let explicit = try values(lower(source.blur(sigma: 1)), x: 2)
        #expect(mild == explicit)
        #expect(mild[0] < 255)
    }

    @Test func largerSigmaSpreadsFurther() throws {
        let source = try grey([0, 0, 0, 0, 255, 0, 0, 0, 0], width: 9)
        let narrow = try values(lower(source.blur(sigma: 0.7)), x: 2)
        let wide = try values(lower(source.blur(sigma: 2.5)), x: 2)
        #expect(wide[0] > narrow[0])
    }

    @Test(arguments: BlurPrecision.allCases)
    func everyPrecisionBlurs(precision: BlurPrecision) throws {
        let image = try lower(grey([0, 0, 255, 0, 0], width: 5).blur(sigma: 1, precision: precision))
        let v1 = try values(image, x: 2)[0]
        #expect(v1 < 255)
    }

    @Test func blurRejectsBadParameters() throws {
        let source = try rgb([1, 2, 3])
        for sigma in [0, -1, Double.nan, .infinity] {
            expectHokusaiError({ try source.blur(sigma: sigma) }) { $0.isInvalidOption }
        }
        for amplitude in [0, -0.1, Double.nan, 11] {
            expectHokusaiError({ try source.blur(sigma: 1, minAmplitude: amplitude) }) { $0.isInvalidOption }
        }
    }

    @Test func blurDoesNotBleedTheColourOfTransparentPixels() throws {
        // White, fully transparent black, white. Blurring colour and alpha
        // independently would drag the middle pixel towards black.
        let source = try rgba([255, 255, 255, 255, 0, 0, 0, 0, 255, 255, 255, 255], width: 3)
        let middle = try values(lower(source.blur(sigma: 1)), x: 1)
        #expect(middle.count == 4)
        #expect(middle[0] >= 250 && middle[1] >= 250 && middle[2] >= 250, "got \(middle)")
        #expect(middle[3] > 0)
    }

    // MARK: - Sharpen

    @Test func defaultAndAdvancedSharpenBothApply() throws {
        let pixels = (0..<8).flatMap { _ in [UInt8]([60, 60, 60, 60, 190, 190, 190, 190]) }
        let source = try grey(pixels, width: 8)
        let plain = try lower(source.sharpen())
        let strong = try lower(source.sharpen(SharpenOptions(sigma: 1, flat: 0, jagged: 8)))
        // Sharpening overshoots on the bright side of an edge.
        let v2 = try values(plain, x: 4, y: 4)[0]
        #expect(v2 > 190)
        let v3 = try values(strong, x: 4, y: 4)[0]
        let v4 = try values(plain, x: 4, y: 4)[0]
        #expect(v3 >= v4)
    }

    @Test func sharpenKeepsAlphaAndRejectsBadOptions() throws {
        let source = try rgba([10, 10, 10, 77, 240, 240, 240, 77], width: 2)
        let image = try lower(source.sharpen())
        #expect(image.bands == 4)
        let v4 = try values(image, x: 0)[3]
        #expect(v4 == 77)
        expectHokusaiError({ try source.sharpen(SharpenOptions(sigma: 0)) }) { $0.isInvalidOption }
        expectHokusaiError({ try source.sharpen(SharpenOptions(jagged: -1)) }) { $0.isInvalidOption }
        expectHokusaiError({ try source.sharpen(SharpenOptions(maxBrightening: .nan)) }) { $0.isInvalidOption }
    }

    // MARK: - Grayscale and tint

    @Test func grayscaleKeepsRGBAndAlpha() throws {
        let image = try lower(rgba([255, 0, 0, 77]).grayscale())
        let pixel = try values(image)
        #expect(image.bands == 4)
        #expect(pixel[0] == pixel[1] && pixel[1] == pixel[2], "channels should be equal, got \(pixel)")
        #expect(pixel[3] == 77)
    }

    @Test func convertingToGrayscaleGivesOneColourChannel() throws {
        let v5 = try lower(rgb([255, 0, 0]).convert(to: .grayscale)).bands
        #expect(v5 == 1)
        let withAlpha = try lower(rgba([255, 0, 0, 77]).convert(to: .grayscale))
        #expect(withAlpha.bands == 2)
        let v6 = try values(withAlpha)[1]
        #expect(v6 == 77)
    }

    @Test func tintKeepsAlphaAndColoursLuminance() throws {
        let image = try lower(rgba([200, 200, 200, 77]).tint(Color(red: 1, green: 0, blue: 0)))
        let pixel = try values(image)
        #expect(pixel.count == 4)
        #expect(pixel[0] > 100 && pixel[1] <= 2 && pixel[2] <= 2, "should be red, got \(pixel)")
        #expect(pixel[3] == 77)
    }

    @Test func tintOfAnOpaqueImageStaysOpaqueRGB() throws {
        let image = try lower(rgb([255, 255, 255]).tint(Color(red: 0.2, green: 0.4, blue: 0.8)))
        #expect(image.bands == 3)
        let v7 = try values(image)
        #expect(near(v7, [51, 102, 204], tolerance: 2))
    }

    // MARK: - Normalize and CLAHE

    @Test func normalizeStretchesBetweenPercentiles() throws {
        let ramp = (0..<40).map { UInt8(100 + $0) }
        let source = try grey(Array((0..<4).map { _ in ramp }.joined()), width: 40)
        let image = try lower(source.normalize(lower: 0, upper: 100))
        let v8 = try values(image, x: 0)[0]
        #expect(v8 == 0)
        let v9 = try values(image, x: 39)[0]
        #expect(v9 == 255)
        let middle = try values(image, x: 20)[0]
        #expect((120...140).contains(middle), "midpoint should map near the middle, got \(middle)")
    }

    @Test func normalizeClipsOutsideThePercentiles() throws {
        // 98 pixels of ramp plus one dark and one bright outlier.
        var ramp = (0..<98).map { UInt8(100 + $0 / 4) }
        ramp.insert(0, at: 0)
        ramp.append(255)
        let source = try grey(ramp, width: ramp.count)
        let image = try lower(source.normalize(lower: 2, upper: 98))
        let v10 = try values(image, x: 0)[0]
        #expect(v10 == 0)
        let v11 = try values(image, x: ramp.count - 1)[0]
        #expect(v11 == 255)
    }

    @Test func normalizeKeepsHueAndAlpha() throws {
        let source = try rgba([100, 120, 140, 90, 140, 160, 180, 90], width: 2)
        let image = try lower(source.normalize(lower: 0, upper: 100))
        #expect(image.bands == 4)
        let v12 = try values(image, x: 0)[3]
        #expect(v12 == 90)
        let v13 = try values(image, x: 1)[3]
        #expect(v13 == 90)
    }

    @Test func aFlatImageIsNotNormalized() throws {
        let source = try grey([120, 120, 120, 120], width: 2)
        let v14 = try values(lower(source.normalize()), x: 0)[0]
        #expect(v14 == 120)
    }

    @Test func normalizeRejectsBadPercentiles() throws {
        let source = try rgb([1, 2, 3])
        for (lower, upper) in [(50.0, 50.0), (60, 40), (-1, 99), (1, 101), (.nan, 99), (1, .infinity)] {
            expectHokusaiError({ try source.normalize(lower: lower, upper: upper) }) { $0.isInvalidOption }
        }
    }

    @Test func claheRaisesLocalContrastOfAFlatRamp() throws {
        let ramp = (0..<64).map { UInt8(100 + $0 * 39 / 63) }
        let source = try grey(Array((0..<64).map { _ in ramp }.joined()), width: 64)
        let image = try lower(source.clahe(width: 8, height: 8, maxSlope: 3))
        var lowest = 255, highest = 0
        for x in 0..<64 {
            let value = try values(image, x: x, y: 32)[0]
            lowest = min(lowest, value)
            highest = max(highest, value)
        }
        #expect(highest - lowest > 39, "range \(lowest)...\(highest) should exceed the input range of 39")
    }

    @Test func claheRejectsBadParameters() throws {
        let source = try rgb([1, 2, 3])
        expectHokusaiError({ try source.clahe(width: 0) }) { $0.isInvalidOption }
        expectHokusaiError({ try source.clahe(maxSlope: -1) }) { $0.isInvalidOption }
    }

    // MARK: - Tone

    @Test func gammaBrightensAndLeavesAlphaAlone() throws {
        let image = try lower(rgba([64, 64, 64, 200]).gamma(2))
        let pixel = try values(image)
        #expect(near(Array(pixel.prefix(3)), [128, 128, 128], tolerance: 2))
        #expect(pixel[3] == 200)
    }

    @Test func gammaRejectsBadValues() throws {
        for value in [0, -1, 0.05, 11, Double.nan, .infinity] {
            expectHokusaiError({ try self.rgb([1, 2, 3]).gamma(value) }) { $0.isInvalidOption }
        }
    }

    @Test func negateInvertsColourAndOnlyInvertsAlphaOnRequest() throws {
        let source = try rgba([100, 150, 200, 60])
        let v15 = try values(lower(source.negate()))
        #expect(v15 == [155, 105, 55, 60])
        let v16 = try values(lower(source.negate(alpha: true)))
        #expect(v16 == [155, 105, 55, 195])
    }

    @Test func medianRemovesIsolatedNoise() throws {
        var pixels = [UInt8](repeating: 100, count: 25)
        pixels[12] = 255
        let image = try lower(grey(pixels, width: 5).median(size: 3))
        let v17 = try values(image, x: 2, y: 2)[0]
        #expect(v17 == 100)
    }

    @Test func medianRejectsBadSizes() throws {
        for size in [0, -3, 102] {
            expectHokusaiError({ try self.rgb([1, 2, 3]).median(size: size) }) { $0.isInvalidOption }
        }
    }

    @Test func thresholdMakesAOneChannelMaskByDefault() throws {
        let source = try rgb([100, 100, 100, 200, 200, 200], width: 2)
        let image = try lower(source.threshold(128))
        #expect(image.bands == 1)
        let v18 = try values(image, x: 0)[0]
        #expect(v18 == 0)
        let v19 = try values(image, x: 1)[0]
        #expect(v19 == 255)
    }

    @Test func thresholdPerBandKeepsTheChannels() throws {
        let image = try lower(rgb([100, 200, 100]).threshold(128, grayscale: false))
        #expect(image.bands == 3)
        let v20 = try values(image)
        #expect(v20 == [0, 255, 0])
    }

    @Test func thresholdKeepsAlpha() throws {
        let image = try lower(rgba([200, 200, 200, 55]).threshold(128))
        #expect(image.bands == 2)
        let v21 = try values(image)
        #expect(v21 == [255, 55])
    }

    @Test func thresholdRejectsBadLevels() throws {
        for level in [-1, 256, Double.nan] {
            expectHokusaiError({ try self.rgb([1, 2, 3]).threshold(level) }) { $0.isInvalidOption }
        }
    }

    @Test func modulateAdjustsBrightnessSaturationAndHue() throws {
        let source = try rgb([200, 80, 40])
        let unchanged = try values(lower(source.modulate()))
        #expect(near(unchanged, [200, 80, 40], tolerance: 2))

        // Zero lightness with its chroma left over clips to a very dark red.
        let dark = try values(lower(source.modulate(brightness: 0)))
        #expect(dark.allSatisfy { $0 <= 80 } && dark[1] <= 5 && dark[2] <= 5, "got \(dark)")

        let desaturated = try values(lower(source.modulate(saturation: 0)))
        #expect(near([desaturated[0]], [desaturated[1]], tolerance: 2) && near([desaturated[1]], [desaturated[2]], tolerance: 2))

        let rotated = try values(lower(source.modulate(hue: 180)))
        #expect(!near(rotated, unchanged, tolerance: 20))
    }

    @Test func modulateKeepsAlpha() throws {
        let image = try lower(rgba([200, 80, 40, 66]).modulate(brightness: 1.2, saturation: 0.8, hue: 30))
        #expect(image.bands == 4)
        let v22 = try values(image)[3]
        #expect(v22 == 66)
    }

    @Test func modulateRejectsBadValues() throws {
        let source = try rgb([1, 2, 3])
        expectHokusaiError({ try source.modulate(brightness: -1) }) { $0.isInvalidOption }
        expectHokusaiError({ try source.modulate(saturation: .nan) }) { $0.isInvalidOption }
        expectHokusaiError({ try source.modulate(hue: .infinity) }) { $0.isInvalidOption }
    }

    // MARK: - Alpha

    @Test func ensureAlphaAddsConstantOpacityOnlyWhenMissing() throws {
        let added = try lower(rgb([10, 20, 30]).ensureAlpha(opacity: 0.5))
        #expect(added.bands == 4)
        let v23 = try values(added)
        #expect(near(v23, [10, 20, 30, 128]))

        let opaque = try lower(rgb([10, 20, 30]).ensureAlpha())
        let v24 = try values(opaque)
        #expect(v24 == [10, 20, 30, 255])

        let existing = try lower(rgba([10, 20, 30, 77]).ensureAlpha(opacity: 0.5))
        let v25 = try values(existing)
        #expect(v25 == [10, 20, 30, 77])
    }

    @Test func ensureAlphaRejectsBadOpacity() throws {
        for opacity in [-0.1, 1.1, Double.nan] {
            expectHokusaiError({ try self.rgb([1, 2, 3]).ensureAlpha(opacity: opacity) }) { $0.isInvalidOption }
        }
    }

    @Test func removeAlphaDropsTheChannelWhereFlattenComposites() throws {
        let source = try rgba([255, 0, 0, 0])
        let dropped = try lower(source.removeAlpha())
        #expect(dropped.bands == 3)
        let v26 = try values(dropped)
        #expect(v26 == [255, 0, 0])

        let flattened = try lower(source.flatten(background: .white))
        #expect(flattened.bands == 3)
        let v27 = try values(flattened)
        #expect(v27 == [255, 255, 255])
    }

    @Test func removeAlphaAndFlattenDoNothingWithoutAlpha() throws {
        let source = try rgb([1, 2, 3])
        let v28 = try values(lower(source.removeAlpha()))
        #expect(v28 == [1, 2, 3])
        let v29 = try values(lower(source.flatten(background: .white)))
        #expect(v29 == [1, 2, 3])
    }

    @Test func flattenWorksOnGreyWithAlpha() throws {
        let source = try Hokusai(data: makePNG(width: 1, height: 1, bands: 2, pixels: [0, 0]))
        let flattened = try lower(source.flatten(background: .white))
        #expect(flattened.bands == 1)
        let v30 = try values(flattened)[0]
        #expect(v30 >= 250)
    }

    // MARK: - Concurrency

    @Test func effectHeavyBranchesEvaluateConcurrently() async throws {
        let base = try Hokusai(data: loadFixtureData(named: "landscape-asym", ext: "jpg")).resize(width: 120)
        async let a = base.grayscale().blur().sharpen().png().data()
        async let b = base.normalize().clahe().gamma().png().data()
        async let c = base.tint(Color(red: 0.8, green: 0.6, blue: 0.4)).modulate(brightness: 1.1).negate().png().data()
        async let d = base.ensureAlpha(opacity: 0.5).median().threshold().png().data()
        let results = try await [a, b, c, d]
        #expect(results.allSatisfy { $0.info.width == 120 && !$0.data.isEmpty })
    }
}
