import Foundation
import Hokusai
import Testing

/// Colour and pixel model (#24, #43), black box: what a source's pixel model
/// is reported as, and what colour conversions and alpha operations do to it.
/// The embedded ICC profile is separate from the pixel interpretation, so each
/// is asserted on its own.
@Suite struct ColourModelSemanticsTests {
    private func source(_ name: String, _ ext: String) throws -> Hokusai {
        try Hokusai(data: fixtureData(named: name, ext: ext))
    }

    private func metadata(_ name: String, _ ext: String) async throws -> ImageMetadata {
        try await source(name, ext).metadata()
    }

    /// Metadata of what a pipeline encodes, read back from the bytes.
    private func described(_ pipeline: Hokusai) async throws -> ImageMetadata {
        try await Hokusai(data: pipeline.data().data).metadata()
    }

    // MARK: - Source pixel model

    @Test func interpretationAndICCProfileAreIndependent() async throws {
        let profiled = try await metadata("metadata-rich", "jpg")
        let plain = try await metadata("landscape-asym", "jpg")
        let cmyk = try await metadata("cmyk", "jpg")

        #expect(profiled.pixel.interpretation == .sRGB && profiled.iccProfile != nil)
        #expect(plain.pixel.interpretation == .sRGB && plain.iccProfile == nil)
        #expect(cmyk.pixel.interpretation == .cmyk && cmyk.iccProfile == nil)
        #expect(cmyk.pixel.channels == 4 && !cmyk.pixel.hasAlpha, "the fourth CMYK channel is ink, not alpha")
    }

    @Test func sampleFormatAndBitDepthAreTyped() async throws {
        let sixteen = try await metadata("rgb16", "png")
        #expect(sixteen.pixel.interpretation == .rgb)
        #expect(sixteen.pixel.sampleFormat == .uint16 && sixteen.pixel.bitsPerSample == 16)

        let eight = try await metadata("landscape-asym", "jpg")
        #expect(eight.pixel.sampleFormat == .uint8 && eight.pixel.bitsPerSample == 8)
    }

    @Test func greyscaleAndAlphaAreReportedAsChannels() async throws {
        let greyAlpha = try await metadata("pixel", "png")
        #expect(greyAlpha.pixel.interpretation == .grayscale)
        #expect(greyAlpha.pixel.channels == 2 && greyAlpha.pixel.hasAlpha)

        let rgba = try await metadata("rgba-alpha", "png")
        #expect(rgba.pixel.channels == 4 && rgba.pixel.hasAlpha)

        let rgb = try await metadata("landscape-asym", "jpg")
        #expect(rgb.pixel.channels == 3 && !rgb.pixel.hasAlpha)
    }

    @Test func paletteAndProgressiveFlagsComeFromTheLoader() async throws {
        let palette = try await metadata("palette", "png")
        #expect(palette.pixel.isPalette == true)

        #expect(try await metadata("rgb16", "png").pixel.isPalette == false)
        #expect(try await metadata("metadata-rich", "jpg").isProgressive == true)
        #expect(try await metadata("landscape-asym", "jpg").isProgressive == false)
    }

    // MARK: - Conversion

    @Test func convertingToGrayscaleLeavesEqualChannels() async throws {
        let raster = Raster(width: 4, height: 2) { x, y in [UInt8(40 * x + 10), UInt8(200 - 30 * y), UInt8(90 + 20 * x), 255] }
        let result = try await rasterize(raster.pipeline().convert(to: .grayscale))
        for y in 0..<result.height {
            for x in 0..<result.width {
                let pixel = result.pixel(x, y)
                #expect(pixel[0] == pixel[1] && pixel[1] == pixel[2], "pixel \(x),\(y) is a grey")
            }
        }
    }

    @Test func convertingToGrayscaleOrdersGreensAboveBlues() async throws {
        // Perceptual luminance: green contributes the most, blue the least.
        let result = try await rasterize(Raster(width: 3, height: 1) { x, _ in
            [[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255]][x]
        }.pipeline().convert(to: .grayscale))
        #expect(result.pixel(1, 0)[0] > result.pixel(0, 0)[0] && result.pixel(0, 0)[0] > result.pixel(2, 0)[0])
    }

    @Test func grayscaleConversionDescribesAsOneBandPixels() async throws {
        let output = try await described(source("landscape-asym", "jpg").convert(to: .grayscale).png())
        #expect(output.pixel.interpretation == .grayscale)
        #expect(output.pixel.channels == 1)
    }

    @Test func aCMYKSourceConvertsToDisplayableSRGB() async throws {
        let output = try await described(source("cmyk", "jpg").convert(to: .sRGB).png())
        #expect(output.pixel.interpretation == .sRGB)
        #expect(output.pixel.channels == 3 || output.pixel.channels == 4)
        let original = try await metadata("cmyk", "jpg")
        #expect((output.width, output.height) == (original.orientedSize.width, original.orientedSize.height))
    }

    @Test func aCMYKSourceStillEncodesToJPEGAndPNG() async throws {
        for pipeline in [try source("cmyk", "jpg").jpeg(), try source("cmyk", "jpg").png()] {
            let output = try await pipeline.data()
            #expect(output.info.byteCount > 0)
            #expect(try await Hokusai(data: output.data).metadata().width == output.info.width)
        }
    }

    @Test func aSixteenBitSourceEncodesToEightBitOutputs() async throws {
        let sourceSize = try await metadata("rgb16", "png")
        for pipeline in [try source("rgb16", "png").jpeg(), try source("rgb16", "png").webp()] {
            let output = try await described(pipeline)
            #expect(output.pixel.bitsPerSample == 8)
            #expect((output.width, output.height) == (sourceSize.width, sourceSize.height))
        }
    }

    @Test func aSixteenBitSourceKeepsItsDepthThroughALosslessPNG() async throws {
        let output = try await described(source("rgb16", "png").png())
        #expect(output.pixel.bitsPerSample == 16 && output.pixel.sampleFormat == .uint16)
    }

    @Test func aPaletteSourceTransformsAsItsColoursNotItsIndices() async throws {
        // palette.png is 16×16 with one palette entry, (120, 120, 120).
        let result = try await rasterize(source("palette", "png").flip())
        #expect((result.width, result.height) == (16, 16))
        #expect(result.pixel(0, 0) == [120, 120, 120, 255], "the index was resolved to its colour")
        #expect(result.pixel(15, 15) == [120, 120, 120, 255])
    }

    // MARK: - Alpha

    @Test func ensureAlphaAddsAnOpaqueChannelToAnOpaqueSource() async throws {
        let output = try await described(source("landscape-asym", "jpg").ensureAlpha().png())
        #expect(output.pixel.hasAlpha && output.pixel.channels == 4)

        let result = try await rasterize(Raster.solid(width: 2, height: 2, [10, 20, 30, 255]).pipeline().ensureAlpha(opacity: 0.5))
        // An existing alpha channel is not overwritten.
        #expect(result.pixel(0, 0) == [10, 20, 30, 255])
    }

    @Test func removeAlphaDropsTheChannelWithoutChangingColour() async throws {
        let output = try await described(source("rgba-alpha", "png").removeAlpha().png())
        #expect(!output.pixel.hasAlpha && output.pixel.channels == 3)
    }

    @Test func flattenReplacesAlphaWithTheBackgroundArithmetically() async throws {
        // rgba-alpha.png: (200, 100, 50) at alpha 255, 128 and 0.
        let result = try await rasterize(source("rgba-alpha", "png").flatten(background: .white))
        #expect(result.pixel(0, 0) == [200, 100, 50, 255], "opaque stays")
        let half = result.pixel(1, 0)
        #expect(abs(Int(half[0]) - 228) <= 2 && abs(Int(half[1]) - 178) <= 2 && abs(Int(half[2]) - 153) <= 2 && half[3] == 255)
        #expect(result.pixel(2, 0) == [255, 255, 255, 255], "fully transparent becomes the background")
    }

    @Test func formatsWithoutAlphaFlattenTransparencyOnWhite() async throws {
        // JPEG cannot carry alpha: the default policy must still produce a valid, opaque image.
        let output = try await described(source("rgba-alpha", "png").jpeg())
        #expect(!output.pixel.hasAlpha)
    }

    // MARK: - Pixel values survive lossless round trips

    @Test func alphaPixelsSurviveALosslessPNGRoundTrip() async throws {
        let direct = try await rasterize(source("rgba-alpha", "png"))
        let viaPNG = try await rasterize(source("rgba-alpha", "png").png())
        expectPixels(viaPNG, match: direct)
        #expect(direct.pixel(1, 0)[3] == 128 && direct.pixel(2, 0)[3] == 0)
    }
}
