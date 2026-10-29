import Foundation
import Hokusai
import Testing

/// Content-aware transforms (#36), black box: trim controls and smart crop.
/// Images are built from exact pixels so the expected geometry is stated, not
/// guessed.
@Suite struct ContentAwareSemanticsTests {
    private let white: [UInt8] = [255, 255, 255, 255]
    private let black: [UInt8] = [0, 0, 0, 255]

    /// An image of `background` with a filled `block` of `foreground`.
    private func blockImage(
        width: Int = 40, height: Int = 40,
        background: [UInt8] = [255, 255, 255, 255],
        foreground: [UInt8] = [0, 0, 0, 255],
        block: (x: Int, y: Int, width: Int, height: Int) = (10, 12, 8, 6)
    ) throws -> Hokusai {
        try Raster(width: width, height: height) { x, y in
            let inside = (block.x..<block.x + block.width).contains(x) && (block.y..<block.y + block.height).contains(y)
            return inside ? foreground : background
        }.pipeline()
    }

    private func size(_ pipeline: Hokusai) async throws -> [Int] {
        let info = try await pipeline.png().data().info
        return [info.width, info.height]
    }

    // MARK: - Trim

    @Test func trimRemovesTheBorderAroundContent() async throws {
        #expect(try await size(blockImage().trim()) == [8, 6])
    }

    @Test func trimKeepsTheContentPixelsExactly() async throws {
        let trimmed = try await rasterize(blockImage().trim())
        expectPixels(trimmed, match: Raster.solid(width: 8, height: 6, black))
    }

    @Test func thresholdControlsHowDifferentContentMustBe() async throws {
        let faint = try blockImage(foreground: [245, 245, 245, 255])
        #expect(try await size(faint.trim(threshold: 5)) == [8, 6])
        #expect(try await size(faint.trim(threshold: 30)) == [40, 40])
    }

    @Test func topLeftPixelIsTheDefaultBackground() async throws {
        let coloured = try blockImage(background: [200, 40, 40, 255], foreground: [255, 255, 255, 255])
        #expect(try await size(coloured.trim()) == [8, 6])
        #expect(try await size(coloured.trim(TrimOptions(background: .topLeft))) == [8, 6])
    }

    @Test func explicitBackgroundOverridesTheTopLeftPixel() async throws {
        let grey = try blockImage(background: [128, 128, 128, 255])
        #expect(try await size(grey.trim(TrimOptions(background: .color(.sRGB8(red: 128, green: 128, blue: 128))))) == [8, 6])
        #expect(try await size(grey.trim(TrimOptions(background: .color(.white)))) == [40, 40], "against white the grey border is content")
    }

    @Test func lineArtFindsThinLinesTheColourScanMisses() async throws {
        let line = try blockImage(block: (14, 10, 1, 20))
        let plain = try await size(line.trim())
        let traced = try await size(line.trim(TrimOptions(lineArt: true)))
        #expect(plain != traced)
        #expect(traced[1] >= 20 && traced[1] < 40)
    }

    @Test func marginKeepsBackgroundAroundContent() async throws {
        #expect(try await size(blockImage().trim(TrimOptions(margin: 3))) == [14, 12])
    }

    @Test func marginIsClampedToTheImage() async throws {
        // The block sits 10 px from the left edge and 12 px from the top.
        #expect(try await size(blockImage().trim(TrimOptions(margin: 100))) == [40, 40])
        #expect(try await size(blockImage().trim(TrimOptions(margin: 11))) == [8 + 10 + 11, 6 + 11 + 11])
    }

    @Test func anAllBackgroundImageIsLeftUnchanged() async throws {
        let blank = try blockImage(block: (0, 0, 0, 0))
        #expect(try await size(blank.trim()) == [40, 40])
        #expect(try await size(blank.trim(TrimOptions(margin: 4))) == [40, 40])
    }

    @Test func trimIsEvaluatedInPipelineOrder() async throws {
        // Trimming first and then extending keeps the extended canvas; extending
        // first lets trim remove the added border again.
        let image = try blockImage()
        let canvas = ImageSize(width: 60, height: 60)
        #expect(try await size(image.trim().extend(to: canvas, background: .white)) == [60, 60])
        #expect(try await size(image.extend(to: canvas, background: .white).trim()) == [8, 6])
    }

    @Test func trimHandlesAnAlphaChannel() async throws {
        // An opaque block on a transparent border.
        let image = try Raster(width: 30, height: 30) { x, y in
            (8..<16).contains(x) && (5..<15).contains(y) ? [255, 0, 0, 255] : [0, 0, 0, 0]
        }.pipeline()
        #expect(try await size(image.trim()) == [8, 10])
    }

    @Test func buildingATrimDoesNotScanPixels() async throws {
        // An explicit colour cannot be compared against CMYK pixels. That is
        // only discovered when the scan runs, so building must succeed.
        let cmyk = try Hokusai(data: fixtureData(named: "cmyk", ext: "jpg"))
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

    // MARK: - Smart crop

    /// A grey field with one saturated, detailed patch in the bottom-right corner.
    private func patchImage() throws -> Hokusai {
        try Raster(width: 120, height: 120) { x, y in
            guard x >= 84, y >= 84 else { return [128, 128, 128, 255] }
            return (x + y).isMultiple(of: 2) ? [255, 30, 30, 255] : [30, 30, 255, 255]
        }.pipeline()
    }

    private func isGrey(_ pixel: [UInt8]) -> Bool { pixel == [128, 128, 128, 255] }

    @Test(arguments: [SmartCropStrategy.attention, .entropy])
    func smartCropProducesTheRequestedSizeAtTheCurrentResolution(strategy: SmartCropStrategy) async throws {
        #expect(try await size(patchImage().smartCrop(width: 40, height: 30, strategy: strategy)) == [40, 30])
    }

    @Test(arguments: [SmartCropStrategy.attention, .entropy])
    func smartCropKeepsTheInterestingRegion(strategy: SmartCropStrategy) async throws {
        let cropped = try await rasterize(patchImage().smartCrop(width: 40, height: 40, strategy: strategy))
        let detail = (0..<cropped.height).reduce(0) { total, y in
            total + (0..<cropped.width).filter { !isGrey(cropped.pixel($0, y)) }.count
        }
        #expect(detail > cropped.width * cropped.height / 4, "a good part of the crop is the patch, not the grey field")
    }

    @Test func smartCropDefaultsToAttention() async throws {
        let explicit = try await rasterize(patchImage().smartCrop(width: 40, height: 40, strategy: .attention))
        let implicit = try await rasterize(patchImage().smartCrop(width: 40, height: 40))
        expectPixels(implicit, match: explicit)
    }

    @Test func smartCropMatchesTheCoverResizeSelection() async throws {
        // A cover resize to the image's own scale is a smart crop.
        let direct = try await rasterize(patchImage().smartCrop(width: 60, height: 120, strategy: .attention))
        let viaCover = try await rasterize(patchImage().resize(width: 60, height: 120, fit: .cover, position: .attention))
        expectPixels(viaCover, match: direct)
    }

    @Test func smartCropIsClampedToTheImage() async throws {
        #expect(try await size(patchImage().smartCrop(width: 500, height: 50)) == [120, 50])
        #expect(try await size(patchImage().smartCrop(width: 500, height: 500)) == [120, 120])
    }

    @Test func smartCropFollowsPipelineOrder() async throws {
        #expect(try await size(patchImage().smartCrop(width: 60, height: 60).resize(width: 30, height: 30, fit: .fill)) == [30, 30])
        // After a resize to 60 px, the 90 px request is clamped to the image.
        #expect(try await size(patchImage().resize(width: 60, height: 60, fit: .fill).smartCrop(width: 90, height: 20)) == [60, 20])
    }

    @Test func invalidSmartCropSizesAreRejectedWhenBuilding() throws {
        let image = try patchImage()
        #expect(throws: HokusaiError.self) { try image.smartCrop(width: 0, height: 10) }
        #expect(throws: HokusaiError.self) { try image.smartCrop(width: 10, height: -1) }
    }

    // MARK: - Concurrency

    @Test func analyticalBranchesOfOneSharedPipelineEvaluateConcurrently() async throws {
        let shared = try patchImage()
        let grey = Color.sRGB8(red: 128, green: 128, blue: 128)
        let seen = try await withThrowingTaskGroup(of: [Int].self) { group in
            for index in 0..<16 {
                group.addTask {
                    index.isMultiple(of: 2)
                        ? try await self.size(shared.smartCrop(width: 30, height: 30, strategy: .entropy))
                        : try await self.size(shared.trim(TrimOptions(background: .color(grey))))
                }
            }
            return try await group.reduce(into: Set<[Int]>()) { $0.insert($1) }
        }
        #expect(seen.count == 2, "each kind of branch gives its own stable result")
    }
}
