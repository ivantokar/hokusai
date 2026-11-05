import Foundation
import Hokusai
import Testing

/// Typed raw pixels in and out (#22): the layout is stated, validated before any native call, and
/// round-trips exactly through the same pipeline an encoded source uses.
@Suite struct RawPixelTests {
    /// A w×h image whose every sample is distinct, so a swapped channel or row shows.
    private func ramp(_ width: Int, _ height: Int, _ format: RawPixelFormat) -> Data {
        var bytes: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width {
                for c in 0..<format.channels {
                    let value = UInt16(truncatingIfNeeded: 17 * (y * width + x) + 61 * c + 3)
                    if format.bytesPerChannel == 1 {
                        bytes.append(UInt8(truncatingIfNeeded: value))
                    } else {
                        let wide = value &* 257
                        bytes.append(UInt8(truncatingIfNeeded: wide))
                        bytes.append(UInt8(truncatingIfNeeded: wide >> 8))
                    }
                }
            }
        }
        return Data(bytes)
    }

    private func sample(_ image: RawImage, x: Int, y: Int, channel: Int) -> Int {
        let size = image.format.bytesPerChannel
        let offset = y * image.rowStride + x * image.format.bytesPerPixel + channel * size
        if size == 1 { return Int(image.data[image.data.startIndex + offset]) }
        return Int(image.data[image.data.startIndex + offset]) | Int(image.data[image.data.startIndex + offset + 1]) << 8
    }

    // MARK: Round trips

    @Test(arguments: RawPixelFormat.allCases)
    func everyFormatRoundTripsByteForByte(format: RawPixelFormat) async throws {
        let pixels = ramp(7, 5, format)
        let image = try Hokusai(raw: pixels, width: 7, height: 5, format: format)
        let output = try await image.raw(format)
        #expect(output.data == pixels)
        #expect(output.width == 7 && output.height == 5)
        #expect(output.format == format)
        #expect(output.rowStride == 7 * format.bytesPerPixel)
        #expect(output.byteCount == output.rowStride * 5)
        #expect(!output.premultiplied)
    }

    @Test func aRawImageFeedsBackIntoAPipeline() async throws {
        let first = try await Hokusai(raw: ramp(6, 4, .rgba8), width: 6, height: 4, format: .rgba8).raw(.rgba8)
        let second = try await Hokusai(raw: first).raw(.rgba8)
        #expect(first == second)
    }

    @Test func channelsAndRowsKeepTheirPlaces() async throws {
        // Row 0: red, green. Row 1: blue, white.
        let pixels = Data([255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255])
        let output = try await Hokusai(raw: pixels, width: 2, height: 2, format: .rgba8).raw(.rgba8)
        #expect([0, 1, 2, 3].map { sample(output, x: 0, y: 0, channel: $0) } == [255, 0, 0, 255])
        #expect([0, 1, 2, 3].map { sample(output, x: 1, y: 0, channel: $0) } == [0, 255, 0, 255])
        #expect([0, 1, 2, 3].map { sample(output, x: 0, y: 1, channel: $0) } == [0, 0, 255, 255])
    }

    // MARK: Row stride

    @Test func paddedRowsAreReadAndOutputIsTight() async throws {
        let rowBytes = 3 * 3, stride = 16
        var padded = Data()
        for y in 0..<2 {
            padded.append(contentsOf: (0..<rowBytes).map { UInt8(10 * y + $0 + 1) })
            padded.append(contentsOf: [UInt8](repeating: 0xEE, count: stride - rowBytes))
        }
        let image = try Hokusai(raw: padded, width: 3, height: 2, format: .rgb8, rowStride: stride)
        let output = try await image.raw(.rgb8)
        #expect(output.rowStride == rowBytes)
        #expect(Array(output.data) == Array(1...9) + Array(11...19))
    }

    @Test func thePaddingAfterTheLastRowMayBeMissing() async throws {
        let stride = 16
        var padded = Data()
        padded.append(contentsOf: [UInt8](repeating: 7, count: stride))
        padded.append(contentsOf: [UInt8](repeating: 9, count: 9))
        let output = try await Hokusai(raw: padded, width: 3, height: 2, format: .rgb8, rowStride: stride).raw(.rgb8)
        #expect(output.data.suffix(9).allSatisfy { $0 == 9 })
    }

    // MARK: Conversion

    @Test func eightBitWhiteBecomesSixteenBitWhiteAndBack() async throws {
        let white = Data([255, 255, 255])
        let wide = try await Hokusai(raw: white, width: 1, height: 1, format: .rgb8).raw(.rgb16)
        #expect([0, 1, 2].map { sample(wide, x: 0, y: 0, channel: $0) } == [65535, 65535, 65535])
        let narrow = try await Hokusai(raw: wide).raw(.rgb8)
        #expect(Array(narrow.data) == [255, 255, 255])
    }

    @Test func greyBecomesRGBAndColourBecomesGrey() async throws {
        let grey = try await Hokusai(raw: Data([100]), width: 1, height: 1, format: .gray8).raw(.rgb8)
        let rgb = (0..<3).map { sample(grey, x: 0, y: 0, channel: $0) }
        #expect(rgb[0] == rgb[1] && rgb[1] == rgb[2], "a grey pixel keeps its value in every channel")
        let colour = try await Hokusai(raw: Data([255, 0, 0]), width: 1, height: 1, format: .rgb8).raw(.gray8)
        let luminance = sample(colour, x: 0, y: 0, channel: 0)
        #expect((100...150).contains(luminance), "red reduces to the grey of its luminance, got \(luminance)")
    }

    @Test func alphaIsAddedOpaqueAndFlattenedOverTheBackground() async throws {
        let opaque = try await Hokusai(raw: Data([10, 20, 30]), width: 1, height: 1, format: .rgb8).raw(.rgba8)
        #expect([0, 1, 2, 3].map { sample(opaque, x: 0, y: 0, channel: $0) } == [10, 20, 30, 255])

        let transparent = Data([255, 0, 0, 0])   // fully transparent red
        let over = try await Hokusai(raw: transparent, width: 1, height: 1, format: .rgba8).raw(.rgb8, background: .white)
        #expect(Array(over.data) == [255, 255, 255])
        let halfRed = Data([255, 0, 0, 128])
        let blended = try await Hokusai(raw: halfRed, width: 1, height: 1, format: .rgba8).raw(.rgb8, background: .white)
        #expect(sample(blended, x: 0, y: 0, channel: 0) == 255)
        #expect((120...135).contains(sample(blended, x: 0, y: 0, channel: 1)))
    }

    @Test func premultipliedInputIsDividedOutAndOutputCanBePremultiplied() async throws {
        // Straight (200, 100, 50) at alpha 128 is premultiplied to about (100, 50, 25).
        let premultiplied = Data([100, 50, 25, 128])
        let straight = try await Hokusai(raw: premultiplied, width: 1, height: 1, format: .rgba8, premultiplied: true).raw(.rgba8)
        #expect(abs(sample(straight, x: 0, y: 0, channel: 0) - 199) <= 2)
        #expect(sample(straight, x: 0, y: 0, channel: 3) == 128)
        let again = try await Hokusai(raw: straight).raw(.rgba8, premultiplied: true)
        #expect(again.premultiplied)
        #expect(abs(sample(again, x: 0, y: 0, channel: 0) - 100) <= 2)
        let flat = try await Hokusai(raw: Data([1, 2, 3]), width: 1, height: 1, format: .rgb8).raw(.rgb8, premultiplied: true)
        #expect(!flat.premultiplied, "a format without alpha is never premultiplied")
    }

    // MARK: Shared pipeline

    @Test func rawAndEncodedSourcesShareTheTransforms() async throws {
        let pixels = ramp(40, 30, .rgba8)
        let resized = try Hokusai(raw: pixels, width: 40, height: 30, format: .rgba8).resize(width: 20, height: 15, fit: .fill)
        let raw = try await resized.raw(.rgba8)
        #expect(raw.width == 20 && raw.height == 15)
        let png = try await Hokusai(raw: pixels, width: 40, height: 30, format: .rgba8).png().data()
        #expect(png.info.width == 40 && png.info.height == 30)
        let decoded = try await Hokusai(data: png.data).raw(.rgba8)
        #expect(decoded.data == pixels, "PNG is lossless, so the pixels survive an encode and decode")
    }

    @Test func rawSourcesDescribeThemselves() async throws {
        let metadata = try await Hokusai(raw: ramp(9, 4, .rgb8), width: 9, height: 4, format: .rgb8).metadata()
        #expect(metadata.width == 9 && metadata.height == 4)
    }

    @Test func aRawOutputIsAlsoReadableFromAnEncodedPipeline() async throws {
        let source = try Hokusai(data: fixtureData(named: "landscape-asym", ext: "jpg")).resize(width: 32)
        let frame = try await source.raw(.rgb8)
        #expect(frame.byteCount == frame.width * frame.height * 3)
        let encoded = try await Hokusai(raw: frame).png().data()
        #expect(encoded.info.width == frame.width)
    }

    @Test func aPipelineBranchedFromARawSourceIsIndependent() async throws {
        let base = try Hokusai(raw: ramp(8, 8, .rgba8), width: 8, height: 8, format: .rgba8)
        async let small = base.resize(width: 4, height: 4, fit: .fill).raw()
        async let full = base.raw()
        let (a, b) = try await (small, full)
        #expect(a.width == 4 && b.width == 8)
    }

    // MARK: Validation

    @Test func theByteCountMustMatchTheGeometry() {
        #expect(throws: HokusaiError.self) { try Hokusai(raw: Data(count: 11), width: 2, height: 2, format: .rgb8) }
        #expect(throws: HokusaiError.self) { try Hokusai(raw: Data(count: 13), width: 2, height: 2, format: .rgb8) }
        #expect(throws: HokusaiError.self) { try Hokusai(raw: Data(), width: 2, height: 2, format: .rgb8) }
        #expect(throws: Never.self) { try Hokusai(raw: Data(count: 12), width: 2, height: 2, format: .rgb8) }
        // 16-bit samples are two bytes: the same 12 bytes are too few for rgb16.
        #expect(throws: HokusaiError.self) { try Hokusai(raw: Data(count: 12), width: 2, height: 2, format: .rgb16) }
    }

    @Test func dimensionsAndStrideAreChecked() {
        let data = Data(count: 64)
        #expect(throws: HokusaiError.self) { try Hokusai(raw: data, width: 0, height: 2, format: .rgba8) }
        #expect(throws: HokusaiError.self) { try Hokusai(raw: data, width: 2, height: -1, format: .rgba8) }
        #expect(throws: HokusaiError.self) { try Hokusai(raw: data, width: 4, height: 2, format: .rgba8, rowStride: 15) }
        #expect(throws: HokusaiError.self) { try Hokusai(raw: data, width: 4, height: 2, format: .rgba8, rowStride: -16) }
    }

    @Test func overflowingGeometryIsRejectedBeforeAnyNativeCall() {
        let data = Data(count: 16)
        let huge = Int(Int32.max)
        #expect(throws: HokusaiError.self) { try Hokusai(raw: data, width: huge, height: huge, format: .rgba16) }
        #expect(throws: HokusaiError.self) { try Hokusai(raw: data, width: 2, height: 2, format: .rgba8, rowStride: Int.max) }
        #expect(throws: HokusaiError.self) { try Hokusai(raw: data, width: Int.max, height: 1, format: .rgba8) }
    }

    @Test func limitsApplyToRawInput() {
        let data = Data(count: 4 * 100 * 100)
        let tight = InputLimits(maxBytes: 1_000, maxPixels: 1_000_000)
        #expect(throws: HokusaiError.self) { try Hokusai(raw: data, width: 100, height: 100, format: .rgba8, limits: tight) }
        let pixels = InputLimits(maxPixels: 99)
        #expect(throws: HokusaiError.self) { try Hokusai(raw: data, width: 100, height: 100, format: .rgba8, limits: pixels) }
    }

    @Test func rawOutputRefusesAnEncoder() async throws {
        let image = try Hokusai(raw: Data(count: 4), width: 1, height: 1, format: .rgba8)
        await #expect(throws: HokusaiError.self) { try await image.png().raw() }
    }

    @Test func formatsDescribeTheirLayout() {
        #expect(RawPixelFormat.rgba16.channels == 4 && RawPixelFormat.rgba16.bytesPerPixel == 8)
        #expect(RawPixelFormat.gray8.bytesPerPixel == 1 && RawPixelFormat.grayAlpha16.bitDepth == 16)
        #expect(RawPixelFormat.rgb8.hasAlpha == false && RawPixelFormat.grayAlpha8.hasAlpha)
        #expect(RawPixelFormat.allCases.allSatisfy { $0.isGray == ($0.channels <= 2) })
    }
}
