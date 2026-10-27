import Foundation
import Testing
@testable import Hokusai

/// Content-aware transforms (#36): trim controls and smart crop. Images are
/// built from exact pixels so the expected geometry is stated, not guessed.
@Suite struct ContentAwareTests {
    init() throws { try Hokusai.initialize() }

    // MARK: - Fixtures

    /// An RGB image of `background` with a filled `block` of `foreground`.
    private func blockImage(
        width: Int = 40, height: Int = 40,
        background: [UInt8] = [255, 255, 255],
        foreground: [UInt8] = [0, 0, 0],
        block: (x: Int, y: Int, width: Int, height: Int) = (10, 12, 8, 6)
    ) throws -> Hokusai {
        var pixels: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width {
                let inside = (block.x..<block.x + block.width).contains(x) && (block.y..<block.y + block.height).contains(y)
                pixels += inside ? foreground : background
            }
        }
        return try Hokusai(data: makePNG(width: width, height: height, bands: 3, pixels: pixels))
    }

    private func size(_ pipeline: Hokusai) async throws -> (width: Int, height: Int) {
        let info = try await pipeline.png().data().info
        return (info.width, info.height)
    }

    // MARK: - Trim

    @Test func trimRemovesTheBorderAroundContent() async throws {
        let result = try await size(blockImage().trim())
        #expect(result == (8, 6))
    }

    @Test func thresholdControlsHowDifferentContentMustBe() async throws {
        let faint = try blockImage(foreground: [245, 245, 245])
        #expect(try await size(faint.trim(threshold: 5)) == (8, 6))
        #expect(try await size(faint.trim(threshold: 30)) == (40, 40))
    }

    @Test func topLeftPixelIsTheDefaultBackground() async throws {
        let coloured = try blockImage(background: [200, 40, 40], foreground: [255, 255, 255])
        #expect(try await size(coloured.trim()) == (8, 6))
        #expect(try await size(coloured.trim(TrimOptions(background: .topLeft))) == (8, 6))
    }

    @Test func explicitBackgroundOverridesTheTopLeftPixel() async throws {
        let grey = try blockImage(background: [128, 128, 128])
        let matching = Color.sRGB8(red: 128, green: 128, blue: 128)
        #expect(try await size(grey.trim(TrimOptions(background: .color(matching)))) == (8, 6))
        // Against white, the grey border is itself content.
        #expect(try await size(grey.trim(TrimOptions(background: .color(.white)))) == (40, 40))
    }

    @Test func lineArtFindsThinLinesTheColourScanMisses() async throws {
        let line = try blockImage(block: (14, 10, 1, 20))
        let plain = try await size(line.trim())
        let traced = try await size(line.trim(TrimOptions(lineArt: true)))
        #expect(plain != traced)
        #expect(traced.height >= 20 && traced.height < 40)
    }

    @Test func marginKeepsBackgroundAroundContent() async throws {
        #expect(try await size(blockImage().trim(TrimOptions(margin: 3))) == (14, 12))
    }

    @Test func marginIsClampedToTheImage() async throws {
        // The block sits 10 px from the left edge and 12 px from the top.
        #expect(try await size(blockImage().trim(TrimOptions(margin: 100))) == (40, 40))
        #expect(try await size(blockImage().trim(TrimOptions(margin: 11))) == (8 + 10 + 11, 6 + 11 + 11))
    }

    @Test func allBackgroundImageIsLeftUnchanged() async throws {
        let blank = try blockImage(block: (0, 0, 0, 0))
        #expect(try await size(blank.trim()) == (40, 40))
        #expect(try await size(blank.trim(TrimOptions(margin: 4))) == (40, 40))
    }

    @Test func trimIsEvaluatedInPipelineOrder() async throws {
        // Trimming first and then extending keeps the extended canvas; extending
        // first lets trim remove the added border again.
        let image = try blockImage()
        let trimThenExtend = try image.trim().extend(to: ImageSize(width: 60, height: 60), background: .white)
        #expect(try await size(trimThenExtend) == (60, 60))
        let extendThenTrim = try image.extend(to: ImageSize(width: 60, height: 60), background: .white).trim()
        #expect(try await size(extendThenTrim) == (8, 6))
    }

    @Test func buildingATrimDoesNotScanPixels() async throws {
        // An explicit colour cannot be compared against CMYK pixels. That is
        // only discovered when the scan runs, so building must succeed.
        let cmyk = try Hokusai(data: loadFixtureData(named: "cmyk", ext: "jpg"))
        let pipeline = try cmyk.trim(TrimOptions(background: .color(.white)))
        await #expect(throws: HokusaiError.self) { try await pipeline.png().data() }
    }

    @Test func invalidTrimOptionsAreRejectedWhenBuilding() throws {
        let image = try blockImage()
        #expect(throws: HokusaiError.self) { try image.trim(threshold: -1) }
        #expect(throws: HokusaiError.self) { try image.trim(threshold: .nan) }
        #expect(throws: HokusaiError.self) { try image.trim(TrimOptions(margin: -1)) }
        #expect(throws: HokusaiError.self) { try image.trim(TrimOptions(background: .color(Color(red: 2, green: 0, blue: 0)))) }
    }

    @Test func trimHandlesAnAlphaChannel() async throws {
        // Opaque block on a transparent border.
        var pixels: [UInt8] = []
        for y in 0..<30 {
            for x in 0..<30 {
                let inside = (8..<16).contains(x) && (5..<15).contains(y)
                pixels += inside ? [255, 0, 0, 255] : [0, 0, 0, 0]
            }
        }
        let image = try Hokusai(data: makePNG(width: 30, height: 30, bands: 4, pixels: pixels))
        #expect(try await size(image.trim()) == (8, 10))
    }

    @Test func trimHandlesGreyImages() async throws {
        var pixels = [UInt8](repeating: 255, count: 30 * 30)
        for y in 10..<18 { for x in 4..<10 { pixels[y * 30 + x] = 0 } }
        let image = try Hokusai(data: makePNG(width: 30, height: 30, bands: 1, pixels: pixels))
        #expect(try await size(image.trim()) == (6, 8))
        #expect(try await size(image.trim(TrimOptions(background: .color(.white)))) == (6, 8))
    }

    // MARK: - Smart crop

    /// A grey field with one saturated, detailed patch in the bottom-right corner.
    private func patchImage() throws -> Hokusai {
        var pixels: [UInt8] = []
        for y in 0..<120 {
            for x in 0..<120 {
                if x >= 84, y >= 84 {
                    pixels += (x + y).isMultiple(of: 2) ? [255, 30, 30] : [30, 30, 255]
                } else {
                    pixels += [128, 128, 128]
                }
            }
        }
        return try Hokusai(data: makePNG(width: 120, height: 120, bands: 3, pixels: pixels))
    }

    @Test(arguments: [SmartCropStrategy.attention, .entropy])
    func smartCropProducesTheRequestedSizeAtTheCurrentResolution(strategy: SmartCropStrategy) async throws {
        let output = try await patchImage().smartCrop(width: 40, height: 30, strategy: strategy).png().data()
        #expect(output.info.width == 40)
        #expect(output.info.height == 30)
    }

    @Test(arguments: [SmartCropStrategy.attention, .entropy])
    func smartCropKeepsTheInterestingRegion(strategy: SmartCropStrategy) async throws {
        let cropped = try patchImage().smartCrop(width: 40, height: 40, strategy: strategy)
        // Plain grey would be removed entirely by trim; anything left is the patch.
        let content = try await size(cropped.trim(TrimOptions(background: .color(Color.sRGB8(red: 128, green: 128, blue: 128)))))
        #expect(content.width >= 20 && content.height >= 20)
    }

    @Test func smartCropDefaultsToAttention() async throws {
        let explicit = try await patchImage().smartCrop(width: 40, height: 40, strategy: .attention).png().data()
        let implicit = try await patchImage().smartCrop(width: 40, height: 40).png().data()
        #expect(explicit.data == implicit.data)
    }

    @Test func smartCropMatchesTheCoverResizeSelection() async throws {
        // A cover resize to the image's own scale is a smart crop.
        let direct = try await patchImage().smartCrop(width: 60, height: 120, strategy: .attention).png().data()
        let viaCover = try await patchImage().resize(width: 60, height: 120, fit: .cover, position: .attention).png().data()
        #expect(direct.data == viaCover.data)
    }

    @Test func smartCropIsClampedToTheImage() async throws {
        let wide = try await size(patchImage().smartCrop(width: 500, height: 50))
        #expect(wide == (120, 50))
        let same = try await size(patchImage().smartCrop(width: 500, height: 500))
        #expect(same == (120, 120))
    }

    @Test func smartCropFollowsPipelineOrder() async throws {
        let cropThenResize = try await size(patchImage().smartCrop(width: 60, height: 60).resize(width: 30, height: 30, fit: .fill))
        #expect(cropThenResize == (30, 30))
        // After a resize to 60 px, the 90 px request is clamped to the image.
        let resizeThenCrop = try await size(patchImage().resize(width: 60, height: 60, fit: .fill).smartCrop(width: 90, height: 20))
        #expect(resizeThenCrop == (60, 20))
    }

    @Test func invalidSmartCropSizesAreRejectedWhenBuilding() throws {
        let image = try patchImage()
        #expect(throws: HokusaiError.self) { try image.smartCrop(width: 0, height: 10) }
        #expect(throws: HokusaiError.self) { try image.smartCrop(width: 10, height: -1) }
    }

    // MARK: - Concurrency

    @Test func analyticalBranchesOfOneSharedPipelineEvaluateConcurrently() async throws {
        let shared = try patchImage()
        try await withThrowingTaskGroup(of: [Int].self) { group in
            for index in 0..<16 {
                group.addTask {
                    if index.isMultiple(of: 2) {
                        let info = try await shared.smartCrop(width: 30, height: 30, strategy: .entropy).png().data().info
                        return [info.width, info.height]
                    }
                    let info = try await shared.trim(TrimOptions(background: .color(Color.sRGB8(red: 128, green: 128, blue: 128)))).png().data().info
                    return [info.width, info.height]
                }
            }
            var seen = Set<[Int]>()
            for try await dimensions in group { seen.insert(dimensions) }
            #expect(seen.count == 2)
            #expect(seen.contains([30, 30]))
        }
    }
}
