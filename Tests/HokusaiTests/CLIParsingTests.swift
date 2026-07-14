import Foundation
import XCTest
import ArgumentParser
@testable import HokusaiCLI
@testable import Hokusai

/// CLI argument parsing and validation, tested without process invocation.
/// `ParsableCommand.parse` runs the same parsing + `validate()` path the real
/// binary uses; thrown `ValidationError`s exit non-zero in a real process.
final class CLIParsingTests: XCTestCase {
    // MARK: - thumbnail command

    func testThumbnailCommandParsesValidArguments() throws {
        let command = try ThumbnailCommand.parse([
            "--input", "in.jpg",
            "--output", "out.jpg",
            "--width", "400",
            "--height", "300",
            "--crop", "attention",
            "--no-rotate",
        ])

        XCTAssertEqual(command.input, "in.jpg")
        XCTAssertEqual(command.output, "out.jpg")
        XCTAssertEqual(command.width, 400)
        XCTAssertEqual(command.height, 300)
        XCTAssertEqual(command.crop, "attention")
        XCTAssertTrue(command.noRotate)
    }

    func testThumbnailCommandDefaults() throws {
        let command = try ThumbnailCommand.parse([
            "--input", "in.jpg", "--output", "out.jpg", "--width", "400",
        ])

        XCTAssertNil(command.height)
        XCTAssertEqual(command.crop, "none")
        XCTAssertFalse(command.noRotate)
    }

    func testThumbnailCommandRequiresWidth() {
        XCTAssertThrowsError(try ThumbnailCommand.parse([
            "--input", "in.jpg", "--output", "out.jpg",
        ]))
    }

    func testThumbnailCommandRejectsZeroAndNegativeWidth() {
        XCTAssertThrowsError(try ThumbnailCommand.parse([
            "--input", "in.jpg", "--output", "out.jpg", "--width", "0",
        ]))
        XCTAssertThrowsError(try ThumbnailCommand.parse([
            "--input", "in.jpg", "--output", "out.jpg", "--width", "-10",
        ]))
    }

    func testThumbnailCommandRejectsInvalidHeight() {
        XCTAssertThrowsError(try ThumbnailCommand.parse([
            "--input", "in.jpg", "--output", "out.jpg", "--width", "400", "--height", "0",
        ]))
        XCTAssertThrowsError(try ThumbnailCommand.parse([
            "--input", "in.jpg", "--output", "out.jpg", "--width", "400", "--height", "-1",
        ]))
    }

    func testThumbnailCommandRejectsWidthAboveInt32Max() {
        XCTAssertThrowsError(try ThumbnailCommand.parse([
            "--input", "in.jpg", "--output", "out.jpg", "--width", "\(Int(Int32.max) + 1)",
        ]))
    }

    func testThumbnailCommandRejectsInvalidCropStrategy() {
        XCTAssertThrowsError(try ThumbnailCommand.parse([
            "--input", "in.jpg", "--output", "out.jpg", "--width", "400",
            "--height", "300", "--crop", "smart",
        ]))
    }

    func testThumbnailCommandRejectsCropWithoutHeight() {
        XCTAssertThrowsError(try ThumbnailCommand.parse([
            "--input", "in.jpg", "--output", "out.jpg", "--width", "400", "--crop", "attention",
        ]))
    }

    // MARK: - resize command validation

    func testResizeCommandRejectsNonPositiveDimensions() {
        XCTAssertThrowsError(try ResizeCommand.parse([
            "--input", "in.jpg", "--output", "out.jpg", "--width", "0",
        ]))
        XCTAssertThrowsError(try ResizeCommand.parse([
            "--input", "in.jpg", "--output", "out.jpg", "--height", "-5",
        ]))
    }

    // MARK: - benchmark thumbnail validation

    func testBenchmarkThumbnailCommandRejectsInvalidDimensions() {
        XCTAssertThrowsError(try BenchmarkThumbnailCommand.parse([
            "--input", "in.jpg", "--width", "0",
        ]))
        XCTAssertThrowsError(try BenchmarkThumbnailCommand.parse([
            "--input", "in.jpg", "--height", "-1",
        ]))
    }

    // MARK: - CLIParser helpers

    func testParseThumbnailCropAcceptsAllDocumentedValues() throws {
        XCTAssertEqual(try CLIParser.parseThumbnailCrop("none"), ThumbnailCrop.none)
        XCTAssertEqual(try CLIParser.parseThumbnailCrop("centre"), .centre)
        XCTAssertEqual(try CLIParser.parseThumbnailCrop("center"), .centre)
        XCTAssertEqual(try CLIParser.parseThumbnailCrop("CENTRE"), .centre)
        XCTAssertEqual(try CLIParser.parseThumbnailCrop("attention"), .attention)
        XCTAssertEqual(try CLIParser.parseThumbnailCrop("entropy"), .entropy)
    }

    func testParseThumbnailCropRejectsUnknownValue() {
        XCTAssertThrowsError(try CLIParser.parseThumbnailCrop("smart"))
        XCTAssertThrowsError(try CLIParser.parseThumbnailCrop(""))
    }

    func testValidateDimensionBounds() throws {
        XCTAssertNoThrow(try CLIParser.validateDimension(1, name: "width"))
        XCTAssertNoThrow(try CLIParser.validateDimension(Int(Int32.max), name: "width"))
        XCTAssertThrowsError(try CLIParser.validateDimension(0, name: "width"))
        XCTAssertThrowsError(try CLIParser.validateDimension(-1, name: "width"))
        XCTAssertThrowsError(try CLIParser.validateDimension(Int(Int32.max) + 1, name: "width"))
    }

    func testParseFormatInfersFromOutputExtension() throws {
        XCTAssertEqual(try CLIParser.parseFormat(nil, fallbackPath: "out.webp"), .webp)
        XCTAssertEqual(try CLIParser.parseFormat("jpg", fallbackPath: nil), .jpeg)
        XCTAssertThrowsError(try CLIParser.parseFormat("bmp2", fallbackPath: nil))
        XCTAssertThrowsError(try CLIParser.parseFormat(nil, fallbackPath: "noextension"))
    }
}
