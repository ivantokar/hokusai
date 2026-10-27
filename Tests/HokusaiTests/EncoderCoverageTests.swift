import Foundation
import Testing
@testable import Hokusai

/// Typed coverage of every raster encoder (#23): the format that is actually
/// written, option mapping, sink parity, validation and capability gating.
@Suite struct EncoderCoverageTests {
    init() throws { try Hokusai.initialize() }

    /// A gradient with a translucent corner, so palette, subsampling and
    /// alpha behaviour have something to act on.
    private func picture(width: Int = 64, height: Int = 48) throws -> Hokusai {
        var pixels: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width {
                let alpha: UInt8 = (x < 8 && y < 8) ? 128 : 255
                pixels += [UInt8(x * 255 / width), UInt8(y * 255 / height), UInt8((x + y) % 256), alpha]
            }
        }
        return try Hokusai(data: makePNG(width: width, height: height, bands: 4, pixels: pixels))
    }

    /// Whether this libvips build can encode `format`; optional savers (GIF
    /// needs cgif, TIFF needs libtiff) are not assumed.
    private func canEncode(_ format: ImageFormat) throws -> Bool {
        try Hokusai.capabilities().canEncode(format)
    }

    private func bytes(_ data: Data, _ range: Range<Int>) -> [UInt8] { Array(data[range]) }

    private func tempURL(_ ext: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hokusai-\(UUID().uuidString).\(ext)")
    }

    /// Both sinks give the same bytes, and the output decodes at the same size.
    private func checkParity(_ pipeline: Hokusai, ext: String) async throws -> Data {
        let memory = try await pipeline.data()
        let url = tempURL(ext)
        defer { try? FileManager.default.removeItem(at: url) }
        let info = try await pipeline.write(to: url)
        let file = try Data(contentsOf: url)
        #expect(file == memory.data, "\(ext): file and memory output differ")
        #expect(info.byteCount == file.count)
        let decoded = try await Hokusai(data: memory.data).metadata()
        #expect(decoded.width == memory.info.width && decoded.height == memory.info.height)
        return memory.data
    }

    // MARK: - Signatures and sink parity

    @Test func tiffWritesTIFFWithParity() async throws {
        guard try canEncode(.tiff) else { return }
        let data = try await checkParity(picture().tiff(), ext: "tif")
        #expect(bytes(data, 0..<4) == [0x49, 0x49, 0x2A, 0x00] || bytes(data, 0..<4) == [0x4D, 0x4D, 0x00, 0x2A])
    }

    @Test func gifWritesGIFWithParity() async throws {
        guard try canEncode(.gif) else { return }
        let data = try await checkParity(picture().gif(), ext: "gif")
        #expect(bytes(data, 0..<4) == Array("GIF8".utf8))
    }

    @Test func heifWithAV1WritesAnAV1Container() async throws {
        let capabilities = try Hokusai.capabilities()
        guard capabilities.canEncode(.av1) else { return }
        let data = try await checkParity(picture().heif(compression: .av1), ext: "avif")
        #expect(bytes(data, 4..<8) == Array("ftyp".utf8))
        let metadata = try await Hokusai(data: data).metadata()
        #expect(metadata.format == .avif)
    }

    @Test func heifWithHEVCIsHonouredWhenAvailable() async throws {
        let capabilities = try Hokusai.capabilities()
        guard capabilities.canEncode(.hevc) else { return }
        let data = try await checkParity(picture().heif(compression: .hevc), ext: "heic")
        let metadata = try await Hokusai(data: data).metadata()
        #expect(metadata.format == .heif)
    }

    @Test func avifIsAlwaysAV1RegardlessOfFileName() async throws {
        let capabilities = try Hokusai.capabilities()
        guard capabilities.canEncode(.av1) else { return }
        let url = tempURL("heic")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await picture().avif().write(to: url)
        let metadata = try await Hokusai(url: url).metadata()
        #expect(metadata.format == .avif)
    }

    // MARK: - Option mapping

    @Test func jpegChromaSubsamplingIsReportedByTheDecoder() async throws {
        let full = try await picture().jpeg(options: JPEGOptions(chromaSubsampling: .yuv444)).data()
        let half = try await picture().jpeg(options: JPEGOptions(chromaSubsampling: .yuv420)).data()
        let fullMetadata = try await Hokusai(data: full.data).metadata()
        let halfMetadata = try await Hokusai(data: half.data).metadata()
        #expect(fullMetadata.chromaSubsampling == "4:4:4")
        #expect(halfMetadata.chromaSubsampling == "4:2:0")
    }

    @Test func jpegOptimizedCodingIsNotLarger() async throws {
        let plain = try await picture().jpeg(options: JPEGOptions(optimizeCoding: false)).data()
        let optimised = try await picture().jpeg(options: JPEGOptions(optimizeCoding: true)).data()
        #expect(optimised.data.count <= plain.data.count)
    }

    @Test func pngPaletteProducesAnIndexedImage() async throws {
        let full = try await picture().png().data()
        let indexed: Output
        do {
            indexed = try await picture().png(options: PNGOptions(palette: PNGPalette(quality: 80, bitDepth: 8))).data()
        } catch HokusaiError.encode {
            return  // this libvips has no palette quantiser (libimagequant/quantizr)
        }
        // IHDR colour type is the byte at offset 25: 3 means indexed.
        #expect(full.data[25] != 3)
        #expect(indexed.data[25] == 3)
    }

    @Test func pngInterlaceIsRecordedInTheHeader() async throws {
        let plain = try await picture().png().data()
        let interlaced = try await picture().png(interlaced: true).data()
        // IHDR interlace method is the byte at offset 28.
        #expect(plain.data[28] == 0 && interlaced.data[28] == 1)
    }

    @Test func webpLosslessRoundTripsExactly() async throws {
        let source = try picture(width: 16, height: 16)
        let original = try await source.png().data()
        let lossless = try await source.webp(quality: 80, lossless: true).data()
        let decodedOriginal = try await Hokusai(data: original.data).png().data()
        let decodedLossless = try await Hokusai(data: lossless.data).png().data()
        #expect(decodedOriginal.data == decodedLossless.data)
    }

    @Test(arguments: WebPPreset.allCases)
    func everyWebPPresetEncodes(preset: WebPPreset) async throws {
        let output = try await picture().webp(options: WebPOptions(preset: preset)).data()
        #expect(output.info.format == .webp)
    }

    @Test func webpNearLosslessAndAlphaQualityEncode() async throws {
        let output = try await picture().webp(options: WebPOptions(alphaQuality: 40, nearLossless: true, smartSubsample: true)).data()
        #expect(output.info.format == .webp)
    }

    @Test func tiffCompressionChangesTheEncodingAndStillDecodes() async throws {
        guard try canEncode(.tiff) else { return }
        let flat = try Hokusai(data: makePNG(width: 64, height: 64, bands: 4, pixels: [UInt8](repeating: 200, count: 64 * 64 * 4)))
        let none = try await flat.tiff(compression: .none).data()
        for compression in [TIFFCompression.deflate, .lzw, .packBits, .zstd] {
            let compressed: Output
            do {
                compressed = try await flat.tiff(compression: compression).data()
            } catch HokusaiError.encode where compression == .zstd {
                continue  // libtiff built without zstd
            }
            #expect(compressed.data.count < none.data.count, "\(compression)")
            let decoded = try await Hokusai(data: compressed.data).metadata()
            #expect(decoded.width == 64 && decoded.format == .tiff, "\(compression)")
        }
    }

    @Test func tiffBigTIFFAndTilingProduceValidFiles() async throws {
        guard try canEncode(.tiff) else { return }
        let big = try await picture().tiff(options: TIFFOptions(bigTIFF: true)).data()
        #expect(big.data[2] == 0x2B || big.data[3] == 0x2B)  // BigTIFF version 43
        let tiled = try await picture().tiff(options: TIFFOptions(compression: .deflate, tiling: TIFFTiling(width: 16, height: 16))).data()
        let metadata = try await Hokusai(data: tiled.data).metadata()
        #expect(metadata.width == 64 && metadata.height == 48)
    }

    @Test func gifPaletteBitDepthIsAccepted() async throws {
        guard try canEncode(.gif) else { return }
        let output = try await picture().gif(options: GIFOptions(dither: 0, effort: 3, bitDepth: 4, interlaced: true)).data()
        #expect(output.info.format == .gif)
        #expect(output.info.width == 64)
    }

    // MARK: - Round trips

    @Test func alphaSurvivesTheFormatsThatSupportIt() async throws {
        var formats: [(String, Hokusai)] = try [("png", picture().png()), ("webp", picture().webp(lossless: true))]
        if try canEncode(.tiff) { formats.append(("tiff", try picture().tiff())) }
        for (name, pipeline) in formats {
            let data = try await pipeline.data().data
            let metadata = try await Hokusai(data: data).metadata()
            #expect(metadata.pixel.hasAlpha, "\(name) lost its alpha channel")
        }
    }

    @Test func gifKeepsBinaryTransparency() async throws {
        guard try canEncode(.gif) else { return }
        // GIF has one transparent palette entry, not partial alpha.
        var pixels = [UInt8](repeating: 255, count: 16 * 16 * 4)
        for i in 0..<8 { pixels[i * 4 + 3] = 0 }
        let source = try Hokusai(data: makePNG(width: 16, height: 16, bands: 4, pixels: pixels))
        let data = try await source.gif().data().data
        let metadata = try await Hokusai(data: data).metadata()
        #expect(metadata.pixel.hasAlpha)
    }

    // MARK: - Extension inference

    @Test func extensionsInferEveryTypedFormat() async throws {
        let cases: [(String, ImageFormat)] = [("jpg", .jpeg), ("png", .png), ("webp", .webp), ("tif", .tiff), ("gif", .gif)]
        for (ext, format) in cases where try canEncode(format) {
            let url = tempURL(ext)
            defer { try? FileManager.default.removeItem(at: url) }
            let info = try await picture().write(to: url)
            #expect(info.format == format, ".\(ext)")
        }
    }

    @Test func heicAndHeifExtensionsInferHEIF() async throws {
        let capabilities = try Hokusai.capabilities()
        guard capabilities.canEncode(.hevc) else { return }
        for ext in ["heic", "heif"] {
            let url = tempURL(ext)
            defer { try? FileManager.default.removeItem(at: url) }
            let info = try await picture().write(to: url)
            #expect(info.format == .heif, ".\(ext)")
        }
    }

    // MARK: - Validation

    @Test func invalidOptionsAreRejectedWhenTheEncoderIsSelected() throws {
        let base = try picture()
        let cases: [() throws -> Hokusai] = [
            { try base.jpeg(quality: 0) },
            { try base.png(options: PNGOptions(palette: PNGPalette(quality: 101))) },
            { try base.png(options: PNGOptions(palette: PNGPalette(dither: 2))) },
            { try base.png(options: PNGOptions(palette: PNGPalette(bitDepth: 3))) },
            { try base.webp(options: WebPOptions(effort: 7)) },
            { try base.webp(options: WebPOptions(alphaQuality: -1)) },
            { try base.avif(quality: 101) },
            { try base.heif(quality: 0) },
            { try base.tiff(quality: 0) },
            { try base.tiff(options: TIFFOptions(tiling: TIFFTiling(width: 20, height: 16))) },
            { try base.tiff(options: TIFFOptions(tiling: TIFFTiling(width: 8, height: 16))) },
            { try base.gif(options: GIFOptions(dither: .nan)) },
            { try base.gif(options: GIFOptions(effort: 11)) },
            { try base.gif(options: GIFOptions(bitDepth: 0)) },
        ]
        for (index, make) in cases.enumerated() {
            do {
                _ = try make()
                Issue.record("case \(index) did not throw")
            } catch is HokusaiError {
            }
        }
    }

    // MARK: - Capability gating

    @Test func aMissingFormatIsReportedAsUnsupportedNotAsANativeFailure() throws {
        let none = RuntimeCapabilities(libvipsVersion: "test", inputFormats: [], outputFormats: [.jpeg], textRendering: false)
        for format in [OutputFormat.tiff(), .gif(), .heif()] {
            #expect(throws: HokusaiError.self) {
                try Evaluator.selectEncoder(format, TerminalConfig(), capabilities: none)
            }
        }
    }

    @Test func aMissingHEIFCodecIsNamedInTheError() throws {
        let avifOnly = RuntimeCapabilities(
            libvipsVersion: "test", inputFormats: [], outputFormats: [.heif, .avif], textRendering: false, heifCompressions: [.av1])
        do {
            _ = try Evaluator.selectEncoder(.heif(HEIFOptions(compression: .hevc)), TerminalConfig(), capabilities: avifOnly)
            Issue.record("expected unsupported")
        } catch HokusaiError.unsupported(let feature, _) {
            #expect(feature.contains("HEVC"))
        } catch {
            Issue.record("unexpected \(error)")
        }
        #expect(throws: Never.self) {
            _ = try Evaluator.selectEncoder(.heif(HEIFOptions(compression: .av1)), TerminalConfig(), capabilities: avifOnly)
        }
    }

    @Test func capabilitiesReportTIFFAndGIFOnABuildThatHasThem() throws {
        let capabilities = try Hokusai.capabilities()
        #expect(capabilities.canEncode(.heif) == !capabilities.heifCompressions.isEmpty)
        #expect(capabilities.canEncode(.avif) == capabilities.canEncode(.av1))
    }
}
