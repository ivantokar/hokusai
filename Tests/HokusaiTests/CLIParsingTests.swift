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

    // MARK: - pipeline benchmark validation

    @Test func pipelineBenchmarkParsesConfiguredArguments() throws {
        let command = try BenchmarkPipelineCommand.parse([
            "--input", "in.jpg", "--sigma", "50", "--quality", "82", "--effort", "6",
            "--vips-concurrency", "4", "--concurrency-sweep",
        ])

        #expect(command.sigma == 50)
        #expect(command.quality == 82)
        #expect(command.effort == 6)
        #expect(command.vipsConcurrency == 4)
        #expect(command.concurrencySweep)
    }

    @Test func pipelineBenchmarkRejectsInvalidOptions() {
        #expect(throws: (any Error).self) {
            try BenchmarkPipelineCommand.parse(["--input", "in.jpg", "--sigma", "0"])
        }
        #expect(throws: (any Error).self) {
            try BenchmarkPipelineCommand.parse(["--input", "in.jpg", "--quality", "101"])
        }
        #expect(throws: (any Error).self) {
            try BenchmarkPipelineCommand.parse(["--input", "in.jpg", "--effort", "10"])
        }
    }

    // MARK: - CLIParser helpers

    @Test func parseThumbnailPositionAcceptsAllDocumentedValues() throws {
        #expect(try CLIParser.parseThumbnailPosition("none") == nil)
        #expect(try CLIParser.parseThumbnailPosition("centre") == .center)
        #expect(try CLIParser.parseThumbnailPosition("center") == .center)
        #expect(try CLIParser.parseThumbnailPosition("CENTRE") == .center)
        #expect(try CLIParser.parseThumbnailPosition("attention") == .attention)
        #expect(try CLIParser.parseThumbnailPosition("entropy") == .entropy)
    }

    @Test func parseThumbnailPositionRejectsUnknownValue() {
        #expect(throws: (any Error).self) { try CLIParser.parseThumbnailPosition("smart") }
        #expect(throws: (any Error).self) { try CLIParser.parseThumbnailPosition("") }
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

    @Test func pipelineOutputSupportsPDF() throws {
        let input = try loadFixtureData(named: "pixel", ext: "png")
        let pipeline = try CLIParser.configurePipelineOutput(
            Hokusai(data: input), format: .pdf, quality: nil, compression: nil,
            progressive: false, stripMetadata: true, lossless: false, effort: nil
        )
        #expect(try pipeline.metadata().width == 1)
    }
}
