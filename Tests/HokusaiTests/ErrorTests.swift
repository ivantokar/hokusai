import Foundation
import XCTest
import CVips
@testable import Hokusai

/// Error semantics across all thumbnail and load entry points, plus the
/// ThumbnailCrop → VipsInteresting mapping coverage.
final class ErrorTests: XCTestCase {
    override func setUpWithError() throws {
        try Hokusai.initialize()
    }

    private func landscapePath() throws -> String {
        try fixturePath(named: "landscape-asym", ext: "jpg")
    }

    private func landscapeData() throws -> Data {
        try loadFixtureData(named: "landscape-asym", ext: "jpg")
    }

    private func loadedImage() throws -> HokusaiImage {
        try Hokusai.image(from: landscapePath())
    }

    // MARK: - Invalid dimensions (file entry point)

    func testZeroWidthThrowsInvalidDimensions() throws {
        let path = try landscapePath()
        XCTAssertThrowsHokusaiError(try Hokusai.thumbnail(from: path, width: 0)) { $0.isInvalidDimensions }
    }

    func testNegativeWidthThrowsInvalidDimensions() throws {
        let path = try landscapePath()
        XCTAssertThrowsHokusaiError(try Hokusai.thumbnail(from: path, width: -5)) { $0.isInvalidDimensions }
    }

    func testZeroHeightThrowsInvalidDimensions() throws {
        let path = try landscapePath()
        XCTAssertThrowsHokusaiError(
            try Hokusai.thumbnail(from: path, width: 100, options: ThumbnailOptions(height: 0))
        ) { $0.isInvalidDimensions }
    }

    func testNegativeHeightThrowsInvalidDimensions() throws {
        let path = try landscapePath()
        XCTAssertThrowsHokusaiError(
            try Hokusai.thumbnail(from: path, width: 100, options: ThumbnailOptions(height: -3))
        ) { $0.isInvalidDimensions }
    }

    func testWidthAboveInt32MaxThrowsInvalidDimensions() throws {
        let path = try landscapePath()
        XCTAssertThrowsHokusaiError(
            try Hokusai.thumbnail(from: path, width: Int(Int32.max) + 1)
        ) { $0.isInvalidDimensions }
    }

    func testHeightAboveInt32MaxThrowsInvalidDimensions() throws {
        let path = try landscapePath()
        XCTAssertThrowsHokusaiError(
            try Hokusai.thumbnail(from: path, width: 100, options: ThumbnailOptions(height: Int(Int32.max) + 1))
        ) { $0.isInvalidDimensions }
    }

    func testCropWithoutHeightThrowsInvalidDimensions() throws {
        let path = try landscapePath()
        XCTAssertThrowsHokusaiError(
            try Hokusai.thumbnail(from: path, width: 100, options: ThumbnailOptions(crop: .attention))
        ) { $0.isInvalidDimensions }
    }

    // MARK: - Invalid dimensions (buffer and image entry points)

    func testBufferThumbnailValidatesDimensions() throws {
        let data = try landscapeData()
        XCTAssertThrowsHokusaiError(try Hokusai.thumbnail(from: data, width: 0)) { $0.isInvalidDimensions }
        XCTAssertThrowsHokusaiError(try Hokusai.thumbnail(from: data, width: -1)) { $0.isInvalidDimensions }
        XCTAssertThrowsHokusaiError(
            try Hokusai.thumbnail(from: data, width: Int(Int32.max) + 1)
        ) { $0.isInvalidDimensions }
        XCTAssertThrowsHokusaiError(
            try Hokusai.thumbnail(from: data, width: 10, options: ThumbnailOptions(height: -2))
        ) { $0.isInvalidDimensions }
    }

    func testImageThumbnailValidatesDimensions() throws {
        let image = try loadedImage()
        XCTAssertThrowsHokusaiError(try image.thumbnail(width: 0)) { $0.isInvalidDimensions }
        XCTAssertThrowsHokusaiError(try image.thumbnail(width: -7)) { $0.isInvalidDimensions }
        XCTAssertThrowsHokusaiError(try image.thumbnail(width: Int(Int32.max) + 1)) { $0.isInvalidDimensions }
        XCTAssertThrowsHokusaiError(
            try image.thumbnail(width: 10, options: ThumbnailOptions(height: 0))
        ) { $0.isInvalidDimensions }
    }

    // MARK: - Missing / empty / malformed input

    func testMissingFileThrowsFileNotFound() {
        XCTAssertThrowsHokusaiError(
            try Hokusai.thumbnail(from: "/nonexistent/definitely-missing.jpg", width: 100)
        ) { $0.isFileNotFound }
        XCTAssertThrowsHokusaiError(
            try Hokusai.image(from: "/nonexistent/definitely-missing.jpg")
        ) { $0.isFileNotFound }
    }

    func testEmptyBufferThrowsInvalidImageData() {
        XCTAssertThrowsHokusaiError(try Hokusai.thumbnail(from: Data(), width: 100)) { $0.isInvalidImageData }
        XCTAssertThrowsHokusaiError(try Hokusai.image(from: Data())) { $0.isInvalidImageData }
    }

    func testGarbageBufferThrowsLoadFailed() {
        let garbage = Data((0..<512).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ 11) })
        XCTAssertThrowsHokusaiError(try Hokusai.thumbnail(from: garbage, width: 100)) { $0.isLoadFailed }
        XCTAssertThrowsHokusaiError(try Hokusai.image(from: garbage)) { $0.isLoadFailed }
    }

    func testCorruptedJpegBufferThrowsLoadFailed() throws {
        // Valid JPEG magic followed by garbage: detected as JPEG, fails to decode.
        var corrupted = Data([0xFF, 0xD8, 0xFF, 0xE0])
        corrupted.append(Data((0..<256).map { UInt8(truncatingIfNeeded: $0 &* 91 &+ 3) }))

        XCTAssertThrowsHokusaiError(try Hokusai.thumbnail(from: corrupted, width: 100)) { $0.isLoadFailed }
    }

    func testLoadFailedPreservesVipsDiagnosticText() throws {
        let garbage = Data(repeating: 0xAB, count: 128)
        do {
            _ = try Hokusai.thumbnail(from: garbage, width: 100)
            XCTFail("expected loadFailed")
        } catch let HokusaiError.loadFailed(message) {
            XCTAssertFalse(message.isEmpty)
            XCTAssertNotEqual(message, "Unknown vips error")
        }
    }

    // MARK: - Crop mapping coverage

    func testThumbnailCropMappingCoversAllCases() {
        // Exhaustive over CaseIterable: a new ThumbnailCrop case fails the
        // mapping switch at compile time, and this test documents the values.
        for crop in ThumbnailCrop.allCases {
            let expected: Int
            switch crop {
            case .none: expected = Int(VIPS_INTERESTING_NONE.rawValue)
            case .centre: expected = Int(VIPS_INTERESTING_CENTRE.rawValue)
            case .attention: expected = Int(VIPS_INTERESTING_ATTENTION.rawValue)
            case .entropy: expected = Int(VIPS_INTERESTING_ENTROPY.rawValue)
            }
            XCTAssertEqual(crop.vipsInterestingRawValue, expected)
        }
    }
}
