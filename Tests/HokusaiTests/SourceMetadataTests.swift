import Foundation
import Testing
@testable import Hokusai

/// `metadata()` reports what the root source said when it was opened (#43).
@Suite struct SourceMetadataTests {
    init() throws { try Hokusai.initialize() }

    // MARK: - Helpers

    private func metadata(_ name: String, _ ext: String, options: InputOptions = .init()) async throws -> ImageMetadata {
        try await Hokusai(url: fixtureURL(named: name, ext: ext), options: options).metadata()
    }

    private func contains(_ data: Data?, _ text: String) -> Bool {
        data?.range(of: Data(text.utf8)) != nil
    }

    private var canDecodeHEIF: Bool {
        (try? Hokusai.capabilities().canDecode(.heif)) ?? false
    }

    // MARK: - Meaning: source, never the pipeline

    @Test func transformsDoNotChangeWhatMetadataReports() async throws {
        let source = try Hokusai(url: fixtureURL(named: "landscape-asym", ext: "jpg"))
        let derived = try source.autoOrient().resize(width: 40).blur().extract(x: 0, y: 0, width: 10, height: 10).webp()

        let original = try await source.metadata()
        let transformed = try await derived.metadata()

        #expect(original == transformed)
        #expect(transformed.width == 320 && transformed.height == 200)
    }

    @Test func autoOrientDoesNotChangeTheSourceSnapshot() async throws {
        let source = try Hokusai(url: fixtureURL(named: "orientation-6", ext: "jpg"))
        let before = try await source.metadata()
        let after = try await source.autoOrient().metadata()

        #expect(before == after)
        #expect(after.orientation == .right)
        // The pipeline itself does rotate: the encoded result has swapped sides.
        let output = try await source.autoOrient().png().data()
        #expect((output.info.width, output.info.height) == (80, 120))
    }

    @Test func aCompositeReportsOnlyItsBaseSource() async throws {
        let base = try Hokusai(url: fixtureURL(named: "landscape-asym", ext: "jpg"))
        let overlay = try Hokusai(url: fixtureURL(named: "pixel", ext: "png"))
        let composite = try base.composite([CompositeLayer(overlay)])

        let baseMetadata = try await base.metadata()
        let compositeMetadata = try await composite.metadata()
        let overlayMetadata = try await overlay.metadata()

        #expect(compositeMetadata == baseMetadata)
        #expect(overlayMetadata.width == 1, "an overlay is inspected through its own value")
    }

    // MARK: - Orientation

    @Test func storedSizeIsNotSwappedByOrientation() async throws {
        let image = try await metadata("orientation-6", "jpg")
        #expect((image.width, image.height) == (120, 80))
        #expect(image.orientation == .right)
        #expect(image.orientedSize == ImageSize(width: 80, height: 120))
    }

    @Test(arguments: ImageOrientation.allCases)
    func orientedSizeSwapsOnlyForQuarterTurnOrientations(orientation: ImageOrientation) {
        let metadata = ImageMetadata(
            width: 120, height: 80, orientation: orientation,
            pixel: PixelMetadata(channels: 3, hasAlpha: false, interpretation: .sRGB, sampleFormat: .uint8))
        let swapped = (5...8).contains(orientation.rawValue)
        #expect(metadata.orientedSize == (swapped ? ImageSize(width: 80, height: 120) : ImageSize(width: 120, height: 80)))
        #expect(orientation.swapsDimensions == swapped)
    }

    @Test func missingOrInvalidOrientationIsNil() async throws {
        // An explicit tag of 1 is a real orientation; no tag at all is nil.
        let tagged = try await metadata("landscape-asym", "jpg")
        #expect(tagged.orientation == .up)

        let untagged = try await metadata("pixel", "png")
        #expect(untagged.orientation == nil)
        #expect(untagged.orientedSize == ImageSize(width: 1, height: 1))

        for value in [-1, 0, 9, 255] {
            #expect(ImageOrientation(nativeValue: value) == nil, "\(value) is not an orientation")
        }
        for value in 1...8 {
            #expect(ImageOrientation(nativeValue: value)?.rawValue == value)
        }
    }

    // MARK: - Source byte size

    @Test func dataSourceByteSizeIsTheInputLength() async throws {
        let data = try loadFixtureData(named: "landscape-asym", ext: "jpg")
        let image = try await Hokusai(data: data).metadata()
        #expect(image.sourceByteSize == data.count)
    }

    @Test func fileSourceByteSizeIsTheFilesystemSize() async throws {
        let url = try fixtureURL(named: "landscape-asym", ext: "jpg")
        let expected = try #require(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let image = try await Hokusai(url: url).metadata()
        #expect(image.sourceByteSize == expected)
    }

    @Test func aGeneratedSourceHasNoEncodedSize() async throws {
        let metadata = try await Hokusai.text("Hi").metadata()
        #expect(metadata.sourceByteSize == nil)
    }

    // MARK: - Pages versus animation

    @Test func multiPageIsNotAnimation() async throws {
        let tiff = try await metadata("multipage", "tif")
        #expect(tiff.pages.count == 3)
        #expect(tiff.animation == nil)
        #expect(!tiff.isAnimated)
        #expect(tiff.format == .tiff)
    }

    @Test func animatedSourcesExposeLoopAndDelays() async throws {
        let gif = try await metadata("animated", "gif")
        #expect(gif.format == .gif)
        #expect(gif.pages.count == 3)
        #expect(gif.isAnimated)
        #expect(gif.animation?.loopCount == 0)
        #expect(gif.animation?.frameDelays.count == 3)

        let webp = try await metadata("animated", "webp")
        #expect(webp.format == .webp)
        #expect(webp.pages.count == 3)
        #expect(webp.animation?.frameDelays == Array(repeating: .milliseconds(100), count: 3))
    }

    @Test func aSinglePageImageHasNeitherPagesNorAnimation() async throws {
        let image = try await metadata("landscape-asym", "jpg")
        #expect(image.pages.count == 1)
        #expect(image.animation == nil)
    }

    @Test func inspectionRespectsTheSelectedPage() async throws {
        let second = try await metadata("multipage", "tif", options: InputOptions(page: 1))
        #expect(second.pages.count == 3)
        #expect((second.width, second.height) == (16, 16))

        do {
            _ = try await metadata("multipage", "tif", options: InputOptions(page: 3))
            Issue.record("expected an out-of-range page to fail")
        } catch HokusaiError.invalidOption(let name, _) {
            #expect(name == "page")
        }
    }

    // MARK: - Format identity

    @Test(.enabled(if: (try? Hokusai.capabilities().canEncode(.avif)) ?? false, "AVIF not available in this libvips build"))
    func avifIsNotMistakenForHEIC() async throws {
        let avif = try await metadata("sample", "avif")
        #expect(avif.format == .avif)
        #expect(avif.pages.primary == 0)
        #expect(avif.pixel.bitsPerSample == 8)
    }

    @Test(.enabled(if: (try? Hokusai.capabilities().canDecode(.heif)) ?? false, "HEIF not available in this libvips build"))
    func heicIsReportedAsHEIF() async throws {
        let heic = try await metadata("sample", "heic")
        #expect(heic.format == .heif)
    }

    @Test func formatsComeFromTheLoaderNotFromNameMunging() {
        let map = NativeImage.sourceFormat
        #expect(map("jpegload", nil) == .jpeg)
        #expect(map("jpegload_source", nil) == .jpeg)
        #expect(map("jpegload_buffer", nil) == .jpeg)
        #expect(map("pngload_source", nil) == .png)
        #expect(map("webpload", nil) == .webp)
        #expect(map("gifload", nil) == .gif)
        #expect(map("tiffload_source", nil) == .tiff)
        #expect(map("svgload", nil) == .svg)
        #expect(map("pdfload", nil) == .pdf)
        #expect(map("heifload_source", "av1") == .avif)
        #expect(map("heifload", "hevc") == .heif)
        #expect(map("heifload", nil) == .heif)
        // Loaders Hokusai does not name, and lookalikes, are unknown rather than guessed.
        #expect(map("jxlload", nil) == nil)
        #expect(map("magickload", nil) == nil)
        #expect(map("notjpegload", nil) == nil)
        #expect(map("jpegloader", nil) == nil)
        #expect(map(nil, nil) == nil)
    }

    // MARK: - Pixel model is independent of ICC

    @Test func pixelInterpretationAndICCProfileAreIndependent() async throws {
        let profiled = try await metadata("metadata-rich", "jpg")
        let plain = try await metadata("landscape-asym", "jpg")
        let cmyk = try await metadata("cmyk", "jpg")

        // Same interpretation, with and without an embedded profile.
        #expect(profiled.pixel.interpretation == .sRGB && profiled.iccProfile != nil)
        #expect(plain.pixel.interpretation == .sRGB && plain.iccProfile == nil)
        // A different interpretation with no profile at all.
        #expect(cmyk.pixel.interpretation == .cmyk && cmyk.iccProfile == nil)
        #expect(cmyk.pixel.channels == 4)
    }

    @Test func sampleFormatAndBitDepthAreTyped() async throws {
        let sixteen = try await metadata("rgb16", "png")
        #expect(sixteen.pixel.interpretation == .rgb)
        #expect(sixteen.pixel.sampleFormat == .uint16)
        #expect(sixteen.pixel.bitsPerSample == 16)

        let eight = try await metadata("landscape-asym", "jpg")
        #expect(eight.pixel.sampleFormat == .uint8)
        #expect(eight.pixel.bitsPerSample == 8)

        let grey = try await metadata("pixel", "png")
        #expect(grey.pixel.interpretation == .grayscale)
        #expect(grey.pixel.channels == 2 && grey.pixel.hasAlpha)
    }

    @Test func paletteAndProgressiveFlagsComeFromTheLoader() async throws {
        let palette = try await metadata("palette", "png")
        #expect(palette.pixel.isPalette == true)
        #expect(palette.isProgressive == true, "the fixture is interlaced")

        let plainPNG = try await metadata("rgb16", "png")
        #expect(plainPNG.pixel.isPalette == false)
        #expect(plainPNG.isProgressive == false)

        let progressiveJPEG = try await metadata("metadata-rich", "jpg")
        #expect(progressiveJPEG.isProgressive == true)
        #expect(progressiveJPEG.chromaSubsampling == "4:2:0")

        let baselineJPEG = try await metadata("landscape-asym", "jpg")
        #expect(baselineJPEG.isProgressive == false)

        let tiff = try await metadata("multipage", "tif")
        #expect(tiff.isProgressive == nil && tiff.pixel.isPalette == nil && tiff.chromaSubsampling == nil)
    }

    // MARK: - Density

    @Test func densityIsOneTypedValueInDPI() async throws {
        let jfif = try await metadata("metadata-rich", "jpg")
        let density = try #require(jfif.density)
        #expect(abs(density.horizontal - 72) < 0.1 && abs(density.vertical - 72) < 0.1)

        let tiff = try await metadata("density-cm", "tif")
        let metric = try #require(tiff.density)
        #expect(abs(metric.horizontal - 300) < 0.1)
        #expect(tiff.densityUnit == .centimetre)
    }

    @Test func aMissingResolutionIsNotReportedAs25Dpi() async throws {
        // libvips reports exactly 1 pixel/mm for a file that recorded nothing.
        let unrecorded = try await metadata("rgb16", "png")
        #expect(unrecorded.density == nil)
        #expect(unrecorded.densityUnit == nil)

        let recorded = try await metadata("pixel", "png")
        let density = try #require(recorded.density)
        #expect(abs(density.horizontal - 72) < 0.1)
        #expect(recorded.densityUnit == nil, "a PNG pHYs chunk carries no preferred unit")
        #expect(NativeImage.density(xres: 1, yres: 1) == nil)
        #expect(NativeImage.density(xres: 1, yres: 2) != nil)
    }

    // MARK: - Embedded blocks

    @Test func embeddedBlocksAreOwnedRawBytes() async throws {
        let image = try await metadata("metadata-rich", "jpg")

        let exif = try #require(image.exif)
        #expect(exif.starts(with: Data("Exif".utf8) + [0, 0]))
        #expect(contains(exif, "hokusai"))

        let xmp = try #require(image.xmp)
        #expect(contains(xmp, "<dc:creator>hokusai</dc:creator>"))
        #expect(image.xmpString?.contains("<dc:creator>hokusai</dc:creator>") == true)

        let iptc = try #require(image.iptc)
        #expect(iptc.starts(with: Data("Photoshop 3.0".utf8)))
        #expect(contains(iptc, "hokusai fixture"))

        let icc = try #require(image.iccProfile)
        #expect(String(decoding: icc[36..<40], as: UTF8.self) == "acsp", "ICC profile signature")
    }

    @Test func imagesWithoutBlocksReportNil() async throws {
        for (name, ext) in [("pixel", "png"), ("cmyk", "jpg")] {
            let image = try await metadata(name, ext)
            #expect(image.exif == nil && image.xmp == nil && image.iptc == nil && image.iccProfile == nil, "\(name).\(ext)")
            #expect(image.xmpString == nil)
        }
        // landscape-asym.jpg carries only an EXIF block.
        let exifOnly = try await metadata("landscape-asym", "jpg")
        #expect(exifOnly.exif != nil && exifOnly.xmp == nil && exifOnly.iptc == nil && exifOnly.iccProfile == nil)
    }

    @Test func xmpTextIsOnlyOfferedForValidUTF8() {
        var metadata = ImageMetadata(
            width: 1, height: 1, pixel: PixelMetadata(channels: 1, hasAlpha: false, interpretation: .grayscale, sampleFormat: .uint8))
        metadata.xmp = Data([0xFF, 0xFE, 0xFD])
        #expect(metadata.xmpString == nil)
        metadata.xmp = Data("<x/>".utf8)
        #expect(metadata.xmpString == "<x/>")
    }

    // MARK: - Failures follow the #42 taxonomy

    @Test func aMissingFileIsAReadIOError() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("missing-\(UUID().uuidString).jpg")
        do {
            _ = try await Hokusai(url: url).metadata()
            Issue.record("expected a read error")
        } catch HokusaiError.io(_, let operation, _) {
            #expect(operation == .read)
        }
    }

    @Test func corruptBytesAreADecodeError() async throws {
        do {
            _ = try await Hokusai(data: Data(repeating: 0xAB, count: 64)).metadata()
            Issue.record("expected a decode error")
        } catch HokusaiError.decode(let context) {
            #expect(context.operation == "decode input data")
        }
    }

    @Test func inspectionReadsTheHeaderNotThePixels() async throws {
        // The truncated JPEG has an intact header: opening succeeds even though
        // decoding its pixels would fail under the default policy.
        let image = try await metadata("truncated", "jpg")
        #expect(image.format == .jpeg)
        #expect(image.width == 320 && image.height == 200)

        let encoded = try Hokusai(url: fixtureURL(named: "truncated", ext: "jpg")).png()
        do {
            _ = try await encoded.data()
            Issue.record("expected decoding the pixels to fail")
        } catch HokusaiError.decode {
        }
    }

    @Test func inspectionIsCancelledWithItsTask() async throws {
        let source = try Hokusai(url: fixtureURL(named: "landscape-asym", ext: "jpg"))
        let task = Task { () async throws -> ImageMetadata in
            while !Task.isCancelled { await Task.yield() }
            return try await source.metadata()
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch is CancellationError {
        }
    }

    @Test func inspectionIsSafeUnderConcurrency() async throws {
        let names = [("landscape-asym", "jpg"), ("metadata-rich", "jpg"), ("multipage", "tif"), ("animated", "webp"), ("pixel", "png")]
        let expected = try await withThrowingTaskGroup(of: ImageMetadata.self) { group in
            for (name, ext) in names { group.addTask { try await self.metadata(name, ext) } }
            return try await group.reduce(into: [ImageMetadata]()) { $0.append($1) }
        }

        try await withThrowingTaskGroup(of: Int.self) { group in
            for index in 0..<40 {
                group.addTask {
                    let (name, ext) = names[index % names.count]
                    let metadata = try await self.metadata(name, ext)
                    return expected.contains(metadata) ? 1 : 0
                }
            }
            for try await matched in group { #expect(matched == 1) }
        }
    }
}
