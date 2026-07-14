import Foundation
import Testing
import ArgumentParser
@testable import HokusaiCLI
@testable import Hokusai

/// CLI argument parsing and validation, tested without process invocation.
/// `ParsableCommand.parse` runs the same parsing + `validate()` path the real
/// binary uses; thrown `ValidationError`s exit non-zero in a real process.
@Suite struct CLIParsingTests {
    // MARK: - thumbnail command

    @Test func thumbnailCommandParsesValidArguments() throws {
        let command = try ThumbnailCommand.parse([
            "--input", "in.jpg",
            "--output", "out.jpg",
            "--width", "400",
            "--height", "300",
            "--crop", "attention",
            "--no-rotate",
        ])

        #expect(command.input == "in.jpg")
        #expect(command.output == "out.jpg")
        #expect(command.width == 400)
        #expect(command.height == 300)
        #expect(command.crop == "attention")
        #expect(command.noRotate)
    }

    @Test func thumbnailCommandDefaults() throws {
        let command = try ThumbnailCommand.parse([
            "--input", "in.jpg", "--output", "out.jpg", "--width", "400",
        ])

        #expect(command.height == nil)
        #expect(command.crop == "none")
        #expect(!command.noRotate)
    }

    @Test func thumbnailCommandRequiresWidth() {
        #expect(throws: (any Error).self) {
            try ThumbnailCommand.parse(["--input", "in.jpg", "--output", "out.jpg"])
        }
    }

    @Test func thumbnailCommandRejectsZeroAndNegativeWidth() {
        #expect(throws: (any Error).self) {
            try ThumbnailCommand.parse(["--input", "in.jpg", "--output", "out.jpg", "--width", "0"])
        }
        #expect(throws: (any Error).self) {
            try ThumbnailCommand.parse(["--input", "in.jpg", "--output", "out.jpg", "--width", "-10"])
        }
    }

    @Test func thumbnailCommandRejectsInvalidHeight() {
        #expect(throws: (any Error).self) {
            try ThumbnailCommand.parse([
                "--input", "in.jpg", "--output", "out.jpg", "--width", "400", "--height", "0",
            ])
        }
        #expect(throws: (any Error).self) {
            try ThumbnailCommand.parse([
                "--input", "in.jpg", "--output", "out.jpg", "--width", "400", "--height", "-1",
            ])
        }
    }

    @Test func thumbnailCommandRejectsWidthAboveInt32Max() {
        #expect(throws: (any Error).self) {
            try ThumbnailCommand.parse([
                "--input", "in.jpg", "--output", "out.jpg", "--width", "\(Int(Int32.max) + 1)",
            ])
        }
    }

    @Test func thumbnailCommandRejectsInvalidCropStrategy() {
        #expect(throws: (any Error).self) {
            try ThumbnailCommand.parse([
                "--input", "in.jpg", "--output", "out.jpg", "--width", "400",
                "--height", "300", "--crop", "smart",
            ])
        }
    }

    @Test func thumbnailCommandRejectsCropWithoutHeight() {
        #expect(throws: (any Error).self) {
            try ThumbnailCommand.parse([
                "--input", "in.jpg", "--output", "out.jpg", "--width", "400", "--crop", "attention",
            ])
        }
    }

    // MARK: - resize command validation

    @Test func resizeCommandRejectsNonPositiveDimensions() {
        #expect(throws: (any Error).self) {
            try ResizeCommand.parse(["--input", "in.jpg", "--output", "out.jpg", "--width", "0"])
        }
        #expect(throws: (any Error).self) {
            try ResizeCommand.parse(["--input", "in.jpg", "--output", "out.jpg", "--height", "-5"])
        }
    }

    // MARK: - benchmark thumbnail validation

    @Test func benchmarkThumbnailCommandRejectsInvalidDimensions() {
        #expect(throws: (any Error).self) {
            try BenchmarkThumbnailCommand.parse(["--input", "in.jpg", "--width", "0"])
        }
        #expect(throws: (any Error).self) {
            try BenchmarkThumbnailCommand.parse(["--input", "in.jpg", "--height", "-1"])
        }
    }

    // MARK: - CLIParser helpers

    @Test func parseThumbnailCropAcceptsAllDocumentedValues() throws {
        #expect(try CLIParser.parseThumbnailCrop("none") == ThumbnailCrop.none)
        #expect(try CLIParser.parseThumbnailCrop("centre") == .centre)
        #expect(try CLIParser.parseThumbnailCrop("center") == .centre)
        #expect(try CLIParser.parseThumbnailCrop("CENTRE") == .centre)
        #expect(try CLIParser.parseThumbnailCrop("attention") == .attention)
        #expect(try CLIParser.parseThumbnailCrop("entropy") == .entropy)
    }

    @Test func parseThumbnailCropRejectsUnknownValue() {
        #expect(throws: (any Error).self) { try CLIParser.parseThumbnailCrop("smart") }
        #expect(throws: (any Error).self) { try CLIParser.parseThumbnailCrop("") }
    }

    @Test func validateDimensionBounds() throws {
        try CLIParser.validateDimension(1, name: "width")
        try CLIParser.validateDimension(Int(Int32.max), name: "width")
        #expect(throws: (any Error).self) { try CLIParser.validateDimension(0, name: "width") }
        #expect(throws: (any Error).self) { try CLIParser.validateDimension(-1, name: "width") }
        #expect(throws: (any Error).self) {
            try CLIParser.validateDimension(Int(Int32.max) + 1, name: "width")
        }
    }

    @Test func parseFormatInfersFromOutputExtension() throws {
        #expect(try CLIParser.parseFormat(nil, fallbackPath: "out.webp") == .webp)
        #expect(try CLIParser.parseFormat("jpg", fallbackPath: nil) == .jpeg)
        #expect(throws: (any Error).self) { try CLIParser.parseFormat("bmp2", fallbackPath: nil) }
        #expect(throws: (any Error).self) { try CLIParser.parseFormat(nil, fallbackPath: "noextension") }
    }
}
