import Foundation
import Testing
@testable import Hokusai

@Suite struct CoreTests {
    init() throws {
        try Hokusai.initialize()
    }

    @Test func loadImageMetadata() throws {
        let data = try loadFixtureData(named: "pixel", ext: "png")
        let image = try Hokusai.image(from: data)
        let metadata = try image.metadata()

        #expect(metadata.width == 1)
        #expect(metadata.height == 1)
        #expect(metadata.channels >= 2)
        #expect(metadata.hasAlpha)
    }

    @Test func loadImageFromFilePath() throws {
        let path = try fixturePath(named: "landscape-asym", ext: "jpg")
        let image = try Hokusai.image(from: path)

        #expect(try image.width == 320)
        #expect(try image.height == 200)
    }

    @Test func resizeImage() throws {
        let data = try loadFixtureData(named: "pixel", ext: "png")
        let image = try Hokusai.image(from: data)
        let resized = try image.resize(width: 8, height: 8)

        #expect(try resized.width == 8)
        #expect(try resized.height == 8)
    }

    @Test func compositeImage() throws {
        let data = try loadFixtureData(named: "pixel", ext: "png")
        let base = try Hokusai.image(from: data)
        let overlay = try Hokusai.image(from: data)
        let output = try base.composite(
            overlay: overlay,
            x: 0,
            y: 0,
            options: CompositeOptions(mode: .over, opacity: 0.5)
        )

        #expect(try output.width == 1)
        #expect(try output.height == 1)
    }

    @Test func drawTextWithVipsBackend() throws {
        let data = try loadFixtureData(named: "pixel", ext: "png")
        let image = try Hokusai.image(from: data)
        let canvas = try image.resize(width: 256, height: 128)

        var options = TextOptions()
        options.font = "sans"
        options.fontSize = 20
        options.color = [255, 255, 255, 255]
        options.strokeColor = [0, 0, 0, 255]
        options.strokeWidth = 1
        options.shadowOffset = (x: 1, y: 1)
        options.shadowColor = [0, 0, 0, 150]

        let output = try canvas.drawText("A", x: 24, y: 48, options: options)
        let png = try output.toBuffer(options: SaveOptions(format: .png))

        #expect(try output.width == 256)
        #expect(try output.height == 128)
        #expect(!png.isEmpty)
    }

    // MARK: - Sequential Access

    @Test func loadWithSequentialAccess() throws {
        let data = try loadFixtureData(named: "pixel", ext: "png")

        // Sequential load must produce the same image as random load.
        let sequential = try Hokusai.image(from: data, options: LoadOptions(access: .sequential))
        let metadata = try sequential.metadata()

        #expect(metadata.width == 1)
        #expect(metadata.height == 1)
        #expect(metadata.hasAlpha)
    }

    @Test func sequentialLoadPresetConvenience() throws {
        let data = try loadFixtureData(named: "landscape-asym", ext: "jpg")

        let image = try Hokusai.image(from: data, options: .sequential)
        #expect(try image.width == 320)
        #expect(try image.height == 200)
    }

    @Test func sequentialSinglePassPipelineProducesOutput() throws {
        // The documented use case: load -> resize -> encode, one forward pass.
        let path = try fixturePath(named: "landscape-asym", ext: "jpg")
        let image = try Hokusai.image(from: path, options: .sequential)
        let output = try image.resize(width: 64, height: 40).toBuffer(options: SaveOptions(format: .jpeg, quality: 85))

        #expect(!output.isEmpty)
    }

    // MARK: - Existing behavior unchanged

    @Test func normalResizeOutputIsValid() throws {
        let data = try loadFixtureData(named: "pixel", ext: "png")
        let image = try Hokusai.image(from: data)
        let resized = try image.resize(width: 16, height: 16)

        #expect(try resized.width == 16)
        #expect(try resized.height == 16)
        let jpeg = try resized.toBuffer(options: SaveOptions(format: .jpeg, quality: 85))
        #expect(!jpeg.isEmpty)
    }

    @Test func defaultLoadOptionsMatchPriorBehavior() throws {
        let data = try loadFixtureData(named: "pixel", ext: "png")

        // Default LoadOptions() must load identically to the pre-options API.
        let explicit = try Hokusai.image(from: data, options: LoadOptions())
        let meta = try explicit.metadata()

        #expect(meta.width == 1)
        #expect(meta.height == 1)
    }

    // MARK: - README example mirror

    /// Mirrors the README "Thumbnail" examples so the documented snippets are
    /// exercised by the suite.
    @Test func readmeThumbnailExamplesCompileAndRun() throws {
        let photoPath = try fixturePath(named: "landscape-asym", ext: "jpg")
        let imageData = try loadFixtureData(named: "landscape-asym", ext: "jpg")

        let thumb = try Hokusai.thumbnail(from: photoPath, width: 40)
        #expect(try thumb.width == 40)

        let opts = ThumbnailOptions(height: 30)
        let bounded = try Hokusai.thumbnail(from: photoPath, width: 40, options: opts)
        #expect(try bounded.height <= 30)

        let cropped = try Hokusai.thumbnail(
            from: photoPath,
            width: 40,
            options: ThumbnailOptions(height: 30, crop: .attention)
        )
        #expect(try cropped.width == 40)
        #expect(try cropped.height == 30)

        let fromBuffer = try Hokusai.thumbnail(from: imageData, width: 40)
        #expect(try fromBuffer.width == 40)

        let image = try Hokusai.image(from: photoPath)
        let fromImage = try image.thumbnail(width: 40)
        #expect(try fromImage.width == 40)
    }
}
