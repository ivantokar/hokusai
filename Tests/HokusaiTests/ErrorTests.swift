import Foundation
import Testing
import CVips
@testable import Hokusai

/// Error semantics across all thumbnail and load entry points, plus the
/// ThumbnailCrop → VipsInteresting mapping coverage.
@Suite struct ErrorTests {
    init() throws {
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

    @Test func zeroWidthThrowsInvalidDimensions() throws {
        let path = try landscapePath()
        expectHokusaiError({ try Hokusai.thumbnail(from: path, width: 0) }) { $0.isInvalidOption }
    }

    @Test func negativeWidthThrowsInvalidDimensions() throws {
        let path = try landscapePath()
        expectHokusaiError({ try Hokusai.thumbnail(from: path, width: -5) }) { $0.isInvalidOption }
    }

    @Test func zeroHeightThrowsInvalidDimensions() throws {
        let path = try landscapePath()
        expectHokusaiError({
            try Hokusai.thumbnail(from: path, width: 100, options: ThumbnailOptions(height: 0))
        }) { $0.isInvalidOption }
    }

    @Test func negativeHeightThrowsInvalidDimensions() throws {
        let path = try landscapePath()
        expectHokusaiError({
            try Hokusai.thumbnail(from: path, width: 100, options: ThumbnailOptions(height: -3))
        }) { $0.isInvalidOption }
    }

    @Test func widthAboveInt32MaxThrowsInvalidDimensions() throws {
        let path = try landscapePath()
        expectHokusaiError({
            try Hokusai.thumbnail(from: path, width: Int(Int32.max) + 1)
        }) { $0.isInvalidOption }
    }

    @Test func heightAboveInt32MaxThrowsInvalidDimensions() throws {
        let path = try landscapePath()
        expectHokusaiError({
            try Hokusai.thumbnail(from: path, width: 100, options: ThumbnailOptions(height: Int(Int32.max) + 1))
        }) { $0.isInvalidOption }
    }

    @Test func cropWithoutHeightThrowsInvalidDimensions() throws {
        let path = try landscapePath()
        expectHokusaiError({
            try Hokusai.thumbnail(from: path, width: 100, options: ThumbnailOptions(crop: .attention))
        }) { $0.isInvalidOption }
    }

    // MARK: - Invalid dimensions (buffer and image entry points)

    @Test func bufferThumbnailValidatesDimensions() throws {
        let data = try landscapeData()
        expectHokusaiError({ try Hokusai.thumbnail(from: data, width: 0) }) { $0.isInvalidOption }
        expectHokusaiError({ try Hokusai.thumbnail(from: data, width: -1) }) { $0.isInvalidOption }
        expectHokusaiError({
            try Hokusai.thumbnail(from: data, width: Int(Int32.max) + 1)
        }) { $0.isInvalidOption }
        expectHokusaiError({
            try Hokusai.thumbnail(from: data, width: 10, options: ThumbnailOptions(height: -2))
        }) { $0.isInvalidOption }
    }

    @Test func imageThumbnailValidatesDimensions() throws {
        let image = try loadedImage()
        expectHokusaiError({ try image.thumbnail(width: 0) }) { $0.isInvalidOption }
        expectHokusaiError({ try image.thumbnail(width: -7) }) { $0.isInvalidOption }
        expectHokusaiError({ try image.thumbnail(width: Int(Int32.max) + 1) }) { $0.isInvalidOption }
        expectHokusaiError({
            try image.thumbnail(width: 10, options: ThumbnailOptions(height: 0))
        }) { $0.isInvalidOption }
    }

    // MARK: - Missing / empty / malformed input

    @Test func missingFileThrowsReadIO() {
        expectHokusaiError({
            try Hokusai.thumbnail(from: "/nonexistent/definitely-missing.jpg", width: 100)
        }) { $0.isReadFailure }
        expectHokusaiError({
            try Hokusai.image(from: "/nonexistent/definitely-missing.jpg")
        }) { $0.isReadFailure }
    }

    @Test func emptyBufferThrowsInvalidInput() {
        expectHokusaiError({ try Hokusai.thumbnail(from: Data(), width: 100) }) { $0.isInvalidInput }
        expectHokusaiError({ try Hokusai.image(from: Data()) }) { $0.isInvalidInput }
    }

    @Test func garbageBufferThrowsDecode() {
        let garbage = Data((0..<512).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ 11) })
        expectHokusaiError({ try Hokusai.thumbnail(from: garbage, width: 100) }) { $0.isDecode }
        expectHokusaiError({ try Hokusai.image(from: garbage) }) { $0.isDecode }
    }

    @Test func corruptedJpegBufferThrowsDecode() throws {
        // Valid JPEG magic followed by garbage: detected as JPEG, fails to decode.
        var corrupted = Data([0xFF, 0xD8, 0xFF, 0xE0])
        corrupted.append(Data((0..<256).map { UInt8(truncatingIfNeeded: $0 &* 91 &+ 3) }))

        expectHokusaiError({ try Hokusai.thumbnail(from: corrupted, width: 100) }) { $0.isDecode }
    }

    @Test func decodeFailureKeepsHokusaiContextAndOptionalDiagnostic() throws {
        let garbage = Data(repeating: 0xAB, count: 128)
        do {
            _ = try Hokusai.thumbnail(from: garbage, width: 100)
            Issue.record("expected a decode error")
        } catch let HokusaiError.decode(context) {
            // The diagnostic comes from libvips' process-global log, so its
            // text is never asserted; the Hokusai-owned fields are.
            #expect(context.operation == "thumbnail input data")
            #expect(!context.reason.isEmpty)
            #expect(context.diagnostic?.isEmpty != true)
        }
    }

    // MARK: - Crop mapping coverage

    @Test func thumbnailCropMappingCoversAllCases() {
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
            #expect(crop.vipsInterestingRawValue == expected)
        }
    }
}
