import Foundation
import Hokusai
import Testing

/// Advanced filters (#26): convolution, linear levels, colour matrix, morphology, edges and
/// channel operations. Inputs are tiny synthetic images so the expected pixels can be written out.
@Suite struct AdvancedFilterTests {
    // MARK: Helpers

    private func rgba(_ width: Int, _ height: Int, _ pixel: (Int, Int) -> [UInt8]) throws -> Hokusai {
        var bytes: [UInt8] = []
        for y in 0..<height { for x in 0..<width { bytes += pixel(x, y) } }
        return try Hokusai(raw: Data(bytes), width: width, height: height, format: .rgba8)
    }

    private func solid(_ width: Int, _ height: Int, _ colour: [UInt8]) throws -> Hokusai {
        try rgba(width, height) { _, _ in colour }
    }

    private func pixel(_ image: RawImage, _ x: Int, _ y: Int) -> [Int] {
        let size = image.format.bytesPerChannel
        return (0..<image.format.channels).map { c in
            let offset = y * image.rowStride + x * image.format.bytesPerPixel + c * size
            let base = image.data.startIndex + offset
            return size == 1 ? Int(image.data[base]) : Int(image.data[base]) | Int(image.data[base + 1]) << 8
        }
    }

    private func close(_ a: [Int], _ b: [Int], by tolerance: Int = 1) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) <= tolerance }
    }

    /// A black image with one white pixel in the middle of 7×7.
    private func dot() throws -> Hokusai {
        try rgba(7, 7) { x, y in x == 3 && y == 3 ? [255, 255, 255, 255] : [0, 0, 0, 255] }
    }

    private func whitePixels(_ image: RawImage) -> Int {
        var count = 0
        for y in 0..<image.height { for x in 0..<image.width where pixel(image, x, y)[0] == 255 { count += 1 } }
        return count
    }

    // MARK: Convolution

    @Test func theIdentityKernelChangesNothing() async throws {
        let source = try rgba(6, 5) { x, y in [UInt8(x * 40), UInt8(y * 50), UInt8(x * y * 9), 255] }
        let identity = try ConvolutionKernel(width: 3, height: 3, values: [0, 0, 0, 0, 1, 0, 0, 0, 0])
        #expect(try await source.convolve(identity).raw() == source.raw())
    }

    @Test func aBoxKernelSpreadsAPointEvenly() async throws {
        let box = try ConvolutionKernel(width: 3, height: 3, values: Array(repeating: 1, count: 9), scale: 9)
        let result = try await dot().convolve(box).raw()
        #expect(result.width == 7 && result.height == 7, "the size is preserved")
        for (x, y) in [(2, 2), (3, 3), (4, 4), (2, 4)] {
            #expect(close(Array(pixel(result, x, y).prefix(3)), [28, 28, 28]), "(\(x), \(y)) = \(pixel(result, x, y))")
        }
        #expect(pixel(result, 0, 0) == [0, 0, 0, 255])
        #expect(pixel(result, 5, 3) == [0, 0, 0, 255])
    }

    @Test func alphaIsLeftAloneByConvolution() async throws {
        let source = try rgba(5, 5) { x, y in [UInt8(x * 50), 100, 100, UInt8(40 + y * 40)] }
        let box = try ConvolutionKernel(width: 3, height: 3, values: Array(repeating: 1, count: 9), scale: 9)
        let result = try await source.convolve(box).raw()
        let before = try await source.raw()
        for y in 0..<5 { for x in 0..<5 { #expect(pixel(result, x, y)[3] == pixel(before, x, y)[3]) } }
    }

    @Test func aZeroSumKernelWithAnOffsetCentresFlatAreasOnGrey() async throws {
        let emboss = try ConvolutionKernel(width: 3, height: 3, values: [-1, -1, -1, -1, 8, -1, -1, -1, -1], offset: 128)
        let result = try await solid(5, 5, [90, 90, 90, 255]).convolve(emboss).raw()
        #expect(close(Array(pixel(result, 2, 2).prefix(3)), [128, 128, 128]))
    }

    @Test func aKernelAppliesToEachColourChannelAlike() async throws {
        let box = try ConvolutionKernel(width: 3, height: 3, values: Array(repeating: 1, count: 9), scale: 9)
        let result = try await solid(5, 5, [30, 120, 210, 255]).convolve(box).raw()
        #expect(close(pixel(result, 2, 2), [30, 120, 210, 255]))
    }

    @Test func convolutionKeepsSixteenBitDepth() async throws {
        var samples: [UInt8] = []
        for _ in 0..<(4 * 4) { samples += [0x00, 0x80] }   // 0x8000 in every grey sample
        let image = try Hokusai(raw: Data(samples), width: 4, height: 4, format: .gray16)
        let box = try ConvolutionKernel(width: 3, height: 3, values: Array(repeating: 1, count: 9), scale: 9)
        let result = try await image.convolve(box).raw(.gray16)
        #expect(close(pixel(result, 2, 2), [0x8000], by: 2))
    }

    @Test func aKernelIsValidatedWhenItIsBuilt() {
        #expect(throws: HokusaiError.self) { try ConvolutionKernel(width: 3, height: 3, values: [1, 2, 3]) }
        #expect(throws: HokusaiError.self) { try ConvolutionKernel(width: 0, height: 3, values: []) }
        #expect(throws: HokusaiError.self) { try ConvolutionKernel(width: -1, height: 1, values: [1]) }
        #expect(throws: HokusaiError.self) { try ConvolutionKernel(width: 52, height: 1, values: Array(repeating: 1, count: 52)) }
        #expect(throws: HokusaiError.self) { try ConvolutionKernel(width: 1, height: 1, values: [.nan]) }
        #expect(throws: HokusaiError.self) { try ConvolutionKernel(width: 1, height: 1, values: [.infinity]) }
        #expect(throws: HokusaiError.self) { try ConvolutionKernel(width: 1, height: 1, values: [1], scale: 0) }
        #expect(throws: HokusaiError.self) { try ConvolutionKernel(width: 1, height: 1, values: [1], scale: .nan) }
        #expect(throws: HokusaiError.self) { try ConvolutionKernel(width: 1, height: 1, values: [1], offset: .infinity) }
        #expect(throws: HokusaiError.self) { try ConvolutionKernel(width: Int.max, height: 2, values: [1]) }
        #expect(throws: Never.self) { try ConvolutionKernel(width: 51, height: 51, values: Array(repeating: 0, count: 51 * 51)) }
    }

    // MARK: Linear

    @Test func linearScalesAndShiftsAndClips() async throws {
        let base = try solid(2, 2, [100, 50, 200, 255])
        #expect(try await base.linear(multiply: 2).raw().data.prefix(4) == Data([200, 100, 255, 255]))
        #expect(try await base.linear(add: -60).raw().data.prefix(4) == Data([40, 0, 140, 255]))
        #expect(close(pixel(try await base.linear(multiply: 0.5, add: 10).raw(), 0, 0), [60, 35, 110, 255]))
    }

    @Test func linearKeepsAlpha() async throws {
        let result = try await solid(2, 2, [100, 100, 100, 77]).linear(multiply: 0.5).raw()
        #expect(pixel(result, 1, 1) == [50, 50, 50, 77])
    }

    @Test func linearScalesItsOffsetForSixteenBit() async throws {
        let image = try Hokusai(raw: Data([0x00, 0x10]), width: 1, height: 1, format: .gray16)   // 0x1000 = 4096
        let result = try await image.linear(add: 10).raw(.gray16)
        #expect(close(pixel(result, 0, 0), [4096 + 10 * 257], by: 2))
    }

    @Test func linearIsValidated() {
        #expect(throws: HokusaiError.self) { try solidFree().linear(multiply: .nan) }
        #expect(throws: HokusaiError.self) { try solidFree().linear(multiply: 1001) }
        #expect(throws: HokusaiError.self) { try solidFree().linear(add: .infinity) }
        #expect(throws: HokusaiError.self) { try solidFree().linear(add: 70000) }
    }

    private func solidFree() throws -> Hokusai { try solid(1, 1, [0, 0, 0, 255]) }

    // MARK: Colour matrix

    @Test func theIdentityMatrixChangesNothing() async throws {
        let source = try rgba(4, 4) { x, y in [UInt8(x * 60), UInt8(y * 60), 77, UInt8(100 + x * 30)] }
        let identity = try ColorMatrix([1, 0, 0, 0, 1, 0, 0, 0, 1])
        #expect(try await source.recombine(identity).raw() == source.raw())
    }

    @Test func sepiaToneIsDeterministicAndKeepsAlpha() async throws {
        let result = try await solid(2, 2, [100, 100, 100, 200]).recombine(.sepia).raw()
        #expect(close(pixel(result, 0, 0), [135, 120, 94, 200]))
        let bright = try await solid(1, 1, [255, 255, 255, 255]).recombine(.sepia).raw()
        #expect(close(pixel(bright, 0, 0), [255, 255, 239, 255]), "red and green clip at 255; blue is 0.937 × 255")
    }

    @Test func channelsCanBeSwappedExactly() async throws {
        let result = try await solid(1, 1, [10, 20, 30, 255]).recombine(.swapRedBlue).raw()
        #expect(pixel(result, 0, 0) == [30, 20, 10, 255])
    }

    @Test func aGreySourceIsReadAsSRGB() async throws {
        let grey = try Hokusai(raw: Data([100]), width: 1, height: 1, format: .gray8)
        let result = try await grey.recombine(.swapRedBlue).raw(.rgb8)
        #expect(close(pixel(result, 0, 0), [100, 100, 100]))
    }

    @Test func aMatrixNeedsNineFiniteCoefficients() {
        #expect(throws: HokusaiError.self) { try ColorMatrix([1, 0, 0, 0, 1, 0]) }
        #expect(throws: HokusaiError.self) { try ColorMatrix(Array(repeating: 0, count: 16)) }
        #expect(throws: HokusaiError.self) { try ColorMatrix([1, 0, 0, 0, 1, 0, 0, 0, .nan]) }
        #expect(throws: Never.self) { try ColorMatrix([1, 0, 0, 0, 1, 0, 0, 0, 1]) }
    }

    // MARK: Morphology

    @Test func dilateGrowsAndErodeShrinksAMask() async throws {
        let grown = try await dot().dilate(radius: 1).raw()
        #expect(whitePixels(grown) == 9, "a point becomes a 3×3 block")
        #expect(pixel(grown, 4, 4)[0] == 255 && pixel(grown, 5, 5)[0] == 0)
        let wider = try await dot().dilate(radius: 2).raw()
        #expect(whitePixels(wider) == 25)
        let shrunk = try await dot().dilate(radius: 1).erode(radius: 1).raw()
        #expect(whitePixels(shrunk) == 1, "dilate then erode closes back to the point")
    }

    @Test func erodeThenDilateRemovesSpecks() async throws {
        let blob = try rgba(9, 9) { x, y in
            let big = (1...5).contains(x) && (1...5).contains(y)
            let speck = x == 7 && y == 7
            return big || speck ? [255, 255, 255, 255] : [0, 0, 0, 255]
        }
        let cleaned = try await blob.erode(radius: 1).dilate(radius: 1).raw()
        #expect(pixel(cleaned, 7, 7)[0] == 0, "the speck is gone")
        #expect(pixel(cleaned, 3, 3)[0] == 255, "the blob stays")
        #expect(whitePixels(cleaned) == 25)
    }

    @Test func morphologyActsOnGreyValuesAndKeepsAlpha() async throws {
        let source = try rgba(5, 5) { x, y in x == 2 && y == 2 ? [200, 200, 200, 90] : [10, 10, 10, 90] }
        let result = try await source.dilate().raw()
        #expect(pixel(result, 1, 1) == [200, 200, 200, 90])
        #expect(pixel(result, 0, 0) == [10, 10, 10, 90])
    }

    @Test func morphologyRadiusIsValidated() throws {
        let image = try dot()
        #expect(throws: HokusaiError.self) { try image.dilate(radius: 0) }
        #expect(throws: HokusaiError.self) { try image.erode(radius: -1) }
        #expect(throws: HokusaiError.self) { try image.dilate(radius: 51) }
    }

    // MARK: Edges

    /// Black on the left half, white on the right: one vertical edge between x = 5 and x = 6.
    private func step() throws -> Hokusai {
        try rgba(12, 8) { x, _ in x < 6 ? [0, 0, 0, 255] : [255, 255, 255, 255] }
    }

    @Test(arguments: [EdgeDetector.sobel, .scharr, .prewitt, .canny(sigma: 1.0)])
    func anEdgeIsStrongOnTheBoundaryAndAbsentFarFromIt(detector: EdgeDetector) async throws {
        let result = try await step().edges(detector).raw(.rgba8)
        let boundary = (4...7).map { pixel(result, $0, 4)[0] }.max() ?? 0
        #expect(boundary >= 100, "\(detector): edge strength \(boundary)")
        #expect(pixel(result, 0, 4)[0] == 0 && pixel(result, 11, 4)[0] == 0, "\(detector): flat areas are dark")
        let colour = pixel(result, 6, 4)
        #expect(colour[0] == colour[1] && colour[1] == colour[2], "the result is one channel")
    }

    @Test func aFlatImageHasNoEdges() async throws {
        for detector in [EdgeDetector.sobel, .scharr, .prewitt, .canny()] {
            let result = try await solid(8, 8, [120, 130, 140, 255]).edges(detector).raw()
            #expect((0..<8).allSatisfy { pixel(result, $0, 4)[0] == 0 }, "\(detector)")
        }
    }

    @Test func aSmallerStepGivesAWeakerEdge() async throws {
        let gentle = try rgba(12, 8) { x, _ in x < 6 ? [100, 100, 100, 255] : [120, 120, 120, 255] }
        func strongest(_ image: RawImage) -> Int { (0..<image.width).map { pixel(image, $0, 4)[0] }.max() ?? 0 }
        let weak = strongest(try await gentle.edges(.sobel).raw())
        let strong = strongest(try await step().edges(.sobel).raw())
        #expect(weak > 0 && weak < strong, "weak \(weak), strong \(strong)")
    }

    @Test func edgesKeepAlpha() async throws {
        let source = try rgba(12, 8) { x, y in [UInt8(x < 6 ? 0 : 255), 0, 0, UInt8(60 + y * 20)] }
        let result = try await source.edges().raw()
        for y in 0..<8 { #expect(pixel(result, 3, y)[3] == 60 + y * 20) }
    }

    @Test func aHorizontalEdgeIsDetectedAsWell() async throws {
        let image = try rgba(8, 12) { _, y in y < 6 ? [0, 0, 0, 255] : [255, 255, 255, 255] }
        let result = try await image.edges(.sobel).raw()
        #expect((4...7).map { pixel(result, 4, $0)[0] }.max()! >= 100)
        #expect(pixel(result, 4, 0)[0] == 0)
    }

    @Test func cannySigmaIsValidated() throws {
        let image = try step()
        #expect(throws: HokusaiError.self) { try image.edges(.canny(sigma: 0)) }
        #expect(throws: HokusaiError.self) { try image.edges(.canny(sigma: .nan)) }
        #expect(throws: HokusaiError.self) { try image.edges(.canny(sigma: 21)) }
        #expect(throws: Never.self) { try image.edges(.canny(sigma: 2)) }
    }

    // MARK: Channels

    @Test func eachNamedChannelBecomesAGreyImage() async throws {
        let source = try solid(2, 2, [200, 100, 50, 80])
        for (channel, expected) in [(Channel.red, 200), (.green, 100), (.blue, 50), (.alpha, 80)] {
            let result = try await source.extractChannel(channel).raw(.gray8)
            #expect(result.format == .gray8)
            #expect(pixel(result, 1, 1) == [expected], "\(channel)")
        }
        let luminance = try await source.extractChannel(.luminance).raw(.gray8)
        #expect((100...150).contains(pixel(luminance, 0, 0)[0]))
    }

    @Test func aGreySourceGivesItsValueAsEveryColourChannel() async throws {
        let grey = try Hokusai(raw: Data([77]), width: 1, height: 1, format: .gray8)
        for channel in [Channel.red, .green, .blue] {
            #expect(close(pixel(try await grey.extractChannel(channel).raw(.gray8), 0, 0), [77]), "\(channel)")
        }
    }

    @Test func sixteenBitChannelsKeepTheirDepth() async throws {
        let image = try Hokusai(raw: Data([0x34, 0x12, 0x00, 0x80, 0xFF, 0xFF]), width: 1, height: 1, format: .rgb16)
        let red = try await image.extractChannel(.red).raw(.gray16)
        #expect(close(pixel(red, 0, 0), [0x1234], by: 2))
    }

    @Test func askingAnOpaqueImageForItsAlphaIsAnError() async throws {
        let opaque = try Hokusai(raw: Data([1, 2, 3]), width: 1, height: 1, format: .rgb8)
        await #expect(throws: HokusaiError.self) { try await opaque.extractChannel(.alpha).raw(.gray8) }
    }

    @Test func aMaskBecomesTheAlphaChannel() async throws {
        let photo = try solid(4, 2, [10, 20, 30, 255])
        let mask = try rgba(4, 2) { x, _ in x < 2 ? [0, 0, 0, 255] : [255, 255, 255, 255] }
        let result = try await photo.withAlpha(from: mask).raw()
        #expect(pixel(result, 0, 0) == [10, 20, 30, 0])
        #expect(pixel(result, 3, 1) == [10, 20, 30, 255])
    }

    @Test func anExistingAlphaIsReplacedAndAMaskCanComeFromAChannel() async throws {
        let donor = try solid(2, 2, [255, 255, 255, 100])
        let photo = try solid(2, 2, [9, 8, 7, 255])
        let result = try await photo.withAlpha(from: donor.extractChannel(.alpha)).raw()
        #expect(pixel(result, 0, 0) == [9, 8, 7, 100])
    }

    @Test func aMaskOfAnotherSizeIsRejected() async throws {
        let photo = try solid(4, 4, [1, 2, 3, 255])
        let mask = try solid(2, 2, [255, 255, 255, 255])
        await #expect(throws: HokusaiError.self) { try await photo.withAlpha(from: mask).raw() }
        let fitted = try await photo.withAlpha(from: mask.resize(width: 4, height: 4, fit: .fill)).raw()
        #expect(fitted.width == 4)
    }

    // MARK: Pipeline semantics

    @Test func operationsApplyInTheOrderTheyAreWritten() async throws {
        let base = try solid(1, 1, [50, 50, 50, 255])
        let first = try await base.linear(multiply: 2).linear(add: 10).raw()
        let second = try await base.linear(add: 10).linear(multiply: 2).raw()
        #expect(pixel(first, 0, 0)[0] == 110 && pixel(second, 0, 0)[0] == 120)
    }

    @Test func anAdvancedPipelineComposesWithEncodersAndEncodedSources() async throws {
        let source = try Hokusai(data: fixtureData(named: "landscape-asym", ext: "jpg")).resize(width: 64)
        let kernel = try ConvolutionKernel(width: 3, height: 3, values: [0, -1, 0, -1, 5, -1, 0, -1, 0])
        let output = try await source.convolve(kernel).recombine(.sepia).dilate().edges().png().data()
        #expect(output.info.width == 64)
    }

    @Test func concurrentEvaluationOfOnePipelineAgrees() async throws {
        let box = try ConvolutionKernel(width: 5, height: 5, values: Array(repeating: 1, count: 25), scale: 25)
        let pipeline = try rgba(40, 40) { x, y in [UInt8(x * 6), UInt8(y * 6), UInt8((x + y) * 3), 255] }
            .convolve(box).recombine(.sepia).erode().edges(.scharr)
        let reference = try await pipeline.raw()
        try await withThrowingTaskGroup(of: RawImage.self) { group in
            for _ in 0..<12 { group.addTask { try await pipeline.raw() } }
            for try await result in group { #expect(result == reference) }
        }
    }
}
