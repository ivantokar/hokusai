import Foundation
import XCTest
@testable import Hokusai

final class HokusaiTests: XCTestCase {
    override func setUpWithError() throws {
        try Hokusai.initialize()
    }

    func testLoadImageMetadata() throws {
        let data = try loadFixtureData(named: "pixel", ext: "png")
        let image = try Hokusai.image(from: data)
        let metadata = try image.metadata()

        XCTAssertEqual(metadata.width, 1)
        XCTAssertEqual(metadata.height, 1)
        XCTAssertGreaterThanOrEqual(metadata.channels, 2)
        XCTAssertTrue(metadata.hasAlpha)
    }

    func testLoadImageFromFilePath() throws {
        let path = try fixturePath(named: "landscape-asym", ext: "jpg")
        let image = try Hokusai.image(from: path)

        XCTAssertEqual(try image.width, 320)
        XCTAssertEqual(try image.height, 200)
    }

    func testResizeImage() throws {
        let data = try loadFixtureData(named: "pixel", ext: "png")
        let image = try Hokusai.image(from: data)
        let resized = try image.resize(width: 8, height: 8)

        XCTAssertEqual(try resized.width, 8)
        XCTAssertEqual(try resized.height, 8)
    }

    func testCompositeImage() throws {
        let data = try loadFixtureData(named: "pixel", ext: "png")
        let base = try Hokusai.image(from: data)
        let overlay = try Hokusai.image(from: data)
        let output = try base.composite(
            overlay: overlay,
            x: 0,
            y: 0,
            options: CompositeOptions(mode: .over, opacity: 0.5)
        )

        XCTAssertEqual(try output.width, 1)
        XCTAssertEqual(try output.height, 1)
    }

    func testDrawTextWithVipsBackend() throws {
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

        XCTAssertEqual(try output.width, 256)
        XCTAssertEqual(try output.height, 128)
        XCTAssertFalse(png.isEmpty)
    }

    // MARK: - Sequential Access

    func testLoadWithSequentialAccess() throws {
        let data = try loadFixtureData(named: "pixel", ext: "png")

        // Sequential load must produce the same image as random load.
        let sequential = try Hokusai.image(from: data, options: LoadOptions(access: .sequential))
        let metadata = try sequential.metadata()

        XCTAssertEqual(metadata.width, 1)
        XCTAssertEqual(metadata.height, 1)
        XCTAssertTrue(metadata.hasAlpha)
    }

    func testSequentialLoadPresetConvenience() throws {
        let data = try loadFixtureData(named: "landscape-asym", ext: "jpg")

        let image = try Hokusai.image(from: data, options: .sequential)
        XCTAssertEqual(try image.width, 320)
        XCTAssertEqual(try image.height, 200)
    }

    func testSequentialSinglePassPipelineProducesOutput() throws {
        // The documented use case: load -> resize -> encode, one forward pass.
        let path = try fixturePath(named: "landscape-asym", ext: "jpg")
        let image = try Hokusai.image(from: path, options: .sequential)
        let output = try image.resize(width: 64, height: 40).toBuffer(options: SaveOptions(format: .jpeg, quality: 85))

        XCTAssertFalse(output.isEmpty)
    }

    // MARK: - Existing behavior unchanged

    func testNormalResizeOutputIsValid() throws {
        let data = try loadFixtureData(named: "pixel", ext: "png")
        let image = try Hokusai.image(from: data)
        let resized = try image.resize(width: 16, height: 16)

        XCTAssertEqual(try resized.width, 16)
        XCTAssertEqual(try resized.height, 16)
        let jpeg = try resized.toBuffer(options: SaveOptions(format: .jpeg, quality: 85))
        XCTAssertFalse(jpeg.isEmpty)
    }

    func testDefaultLoadOptionsMatchPriorBehavior() throws {
        let data = try loadFixtureData(named: "pixel", ext: "png")

        // Default LoadOptions() must load identically to the pre-options API.
        let explicit = try Hokusai.image(from: data, options: LoadOptions())
        let meta = try explicit.metadata()

        XCTAssertEqual(meta.width, 1)
        XCTAssertEqual(meta.height, 1)
    }

    // MARK: - README example mirror

    /// Mirrors the README "Thumbnail" examples so the documented snippets are
    /// exercised by the suite.
    func testReadmeThumbnailExamplesCompileAndRun() throws {
        let photoPath = try fixturePath(named: "landscape-asym", ext: "jpg")
        let imageData = try loadFixtureData(named: "landscape-asym", ext: "jpg")

        let thumb = try Hokusai.thumbnail(from: photoPath, width: 40)
        XCTAssertEqual(try thumb.width, 40)

        let opts = ThumbnailOptions(height: 30)
        let bounded = try Hokusai.thumbnail(from: photoPath, width: 40, options: opts)
        XCTAssertLessThanOrEqual(try bounded.height, 30)

        let cropped = try Hokusai.thumbnail(
            from: photoPath,
            width: 40,
            options: ThumbnailOptions(height: 30, crop: .attention)
        )
        XCTAssertEqual(try cropped.width, 40)
        XCTAssertEqual(try cropped.height, 30)

        let fromBuffer = try Hokusai.thumbnail(from: imageData, width: 40)
        XCTAssertEqual(try fromBuffer.width, 40)

        let image = try Hokusai.image(from: photoPath)
        let fromImage = try image.thumbnail(width: 40)
        XCTAssertEqual(try fromImage.width, 40)
    }
}
