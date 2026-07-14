import Foundation
import XCTest
@testable import Hokusai

/// Thumbnail geometry, crop, and orientation behavior.
///
/// Sources: `landscape-asym.jpg` (320×200, detail near the left edge),
/// `portrait-asym.jpg` (200×320, detail near the top),
/// `orientation-6.jpg` (physical 120×80, EXIF Orientation=6 → displays 80×120).
final class ThumbnailTests: XCTestCase {
    override func setUpWithError() throws {
        try Hokusai.initialize()
    }

    // MARK: - File, buffer, and image entry points

    func testThumbnailFromFilePath() throws {
        let path = try fixturePath(named: "landscape-asym", ext: "jpg")
        let thumb = try Hokusai.thumbnail(from: path, width: 160)

        XCTAssertEqual(try thumb.width, 160)
        XCTAssertEqual(try thumb.height, 100)
    }

    func testThumbnailFromBuffer() throws {
        let data = try loadFixtureData(named: "landscape-asym", ext: "jpg")
        let thumb = try Hokusai.thumbnail(from: data, width: 160)

        XCTAssertEqual(try thumb.width, 160)
        XCTAssertEqual(try thumb.height, 100)
    }

    func testThumbnailFromLoadedImage() throws {
        let path = try fixturePath(named: "landscape-asym", ext: "jpg")
        let image = try Hokusai.image(from: path)
        let thumb = try image.thumbnail(width: 160)

        XCTAssertEqual(try thumb.width, 160)
        XCTAssertEqual(try thumb.height, 100)
    }

    // MARK: - Geometry

    func testWidthOnlyPreservesAspectRatioLandscape() throws {
        let path = try fixturePath(named: "landscape-asym", ext: "jpg")
        let thumb = try Hokusai.thumbnail(from: path, width: 80)

        // 320×200 at width 80 → height 50.
        XCTAssertEqual(try thumb.width, 80)
        XCTAssertEqual(try thumb.height, 50)
    }

    func testWidthOnlyPreservesAspectRatioPortrait() throws {
        // Regression test: vips_thumbnail defaults an unset height to `width`
        // (a square bound), which would give a portrait source a width smaller
        // than requested. The shim passes VIPS_MAX_COORD to keep the promise
        // "width is the target, height follows the aspect ratio".
        let path = try fixturePath(named: "portrait-asym", ext: "jpg")
        let thumb = try Hokusai.thumbnail(from: path, width: 100)

        // 200×320 at width 100 → height 160.
        XCTAssertEqual(try thumb.width, 100)
        XCTAssertEqual(try thumb.height, 160)
    }

    func testWidthAndHeightWithoutCropFitsInside() throws {
        let path = try fixturePath(named: "landscape-asym", ext: "jpg")
        let thumb = try Hokusai.thumbnail(from: path, width: 160, options: ThumbnailOptions(height: 80))

        // Fit 320×200 inside 160×80 → scale 0.4 → 128×80.
        XCTAssertEqual(try thumb.width, 128)
        XCTAssertEqual(try thumb.height, 80)
    }

    func testSourceSmallerThanTargetIsUpscaled() throws {
        // libvips default (VIPS_SIZE_BOTH): thumbnail upscales small sources.
        let path = try fixturePath(named: "landscape-asym", ext: "jpg")
        let thumb = try Hokusai.thumbnail(from: path, width: 640)

        XCTAssertEqual(try thumb.width, 640)
        XCTAssertEqual(try thumb.height, 400)
    }

    func testSourceLargerThanTargetIsDownscaled() throws {
        let path = try fixturePath(named: "portrait-asym", ext: "jpg")
        let thumb = try Hokusai.thumbnail(from: path, width: 50, options: ThumbnailOptions(height: 80))

        // Fit 200×320 inside 50×80 → both bounds active → 50×80.
        XCTAssertEqual(try thumb.width, 50)
        XCTAssertEqual(try thumb.height, 80)
    }

    // MARK: - Crop strategies

    func testCentreCropProducesExactDimensions() throws {
        let path = try fixturePath(named: "landscape-asym", ext: "jpg")
        let thumb = try Hokusai.thumbnail(
            from: path, width: 100, options: ThumbnailOptions(height: 100, crop: .centre))

        XCTAssertEqual(try thumb.width, 100)
        XCTAssertEqual(try thumb.height, 100)
    }

    func testAttentionCropProducesExactDimensions() throws {
        let path = try fixturePath(named: "landscape-asym", ext: "jpg")
        let thumb = try Hokusai.thumbnail(
            from: path, width: 100, options: ThumbnailOptions(height: 100, crop: .attention))

        XCTAssertEqual(try thumb.width, 100)
        XCTAssertEqual(try thumb.height, 100)
    }

    func testEntropyCropProducesExactDimensions() throws {
        let path = try fixturePath(named: "landscape-asym", ext: "jpg")
        let thumb = try Hokusai.thumbnail(
            from: path, width: 100, options: ThumbnailOptions(height: 100, crop: .entropy))

        XCTAssertEqual(try thumb.width, 100)
        XCTAssertEqual(try thumb.height, 100)
    }

    func testAttentionCropSelectsDifferentRegionThanCentre() throws {
        // The fixture's only detailed content sits near the left edge, so a
        // content-aware crop must select different pixels than a centre crop.
        let path = try fixturePath(named: "landscape-asym", ext: "jpg")

        let centre = try Hokusai.thumbnail(
            from: path, width: 100, options: ThumbnailOptions(height: 100, crop: .centre))
        let attention = try Hokusai.thumbnail(
            from: path, width: 100, options: ThumbnailOptions(height: 100, crop: .attention))

        let centrePNG = try centre.toBuffer(options: SaveOptions(format: .png))
        let attentionPNG = try attention.toBuffer(options: SaveOptions(format: .png))
        XCTAssertNotEqual(centrePNG, attentionPNG, "attention crop should select a different region than centre")
    }

    // MARK: - EXIF orientation

    func testExifAutoRotationAppliedByDefault() throws {
        let path = try fixturePath(named: "orientation-6", ext: "jpg")
        let thumb = try Hokusai.thumbnail(from: path, width: 40)

        // Physical 120×80 + Orientation=6 displays as 80×120 → width 40 → 40×60.
        XCTAssertEqual(try thumb.width, 40)
        XCTAssertEqual(try thumb.height, 60)
    }

    func testExifAutoRotationAppliedForBufferSource() throws {
        let data = try loadFixtureData(named: "orientation-6", ext: "jpg")
        let thumb = try Hokusai.thumbnail(from: data, width: 40)

        XCTAssertEqual(try thumb.width, 40)
        XCTAssertEqual(try thumb.height, 60)
    }

    func testNoRotateSkipsExifAutoRotation() throws {
        let path = try fixturePath(named: "orientation-6", ext: "jpg")
        let thumb = try Hokusai.thumbnail(from: path, width: 40, options: ThumbnailOptions(noRotate: true))

        // Without rotation the physical 120×80 frame applies: width 40 →
        // height ≈ 27 (rounding is libvips'), and the result stays landscape.
        let width = try thumb.width
        let height = try thumb.height
        XCTAssertEqual(width, 40)
        XCTAssertTrue((26...28).contains(height), "expected ~27, got \(height)")
        XCTAssertLessThan(height, width)
    }
}
