import ArgumentParser
import Foundation
import Hokusai
import Testing
@testable import HokusaiCommandLine

/// Each command run in-process against real fixtures, checked through the
/// public API by reading the written file back.
@Suite struct CommandEndToEndTests {
    private let landscape: String
    private let rich: String
    private let rotated: String
    private let scratch: ScratchDirectory

    init() throws {
        landscape = try fixturePath(named: "landscape-asym", ext: "jpg")
        rich = try fixturePath(named: "metadata-rich", ext: "jpg")
        rotated = try fixturePath(named: "orientation-6", ext: "jpg")
        scratch = try ScratchDirectory()
    }

    private func metadata(_ path: String) async throws -> ImageMetadata {
        try await Hokusai(url: URL(fileURLWithPath: path)).metadata()
    }

    // MARK: - Happy paths

    @Test func resizeWritesTheRequestedSize() async throws {
        defer { scratch.remove() }
        let out = scratch.path("resized.png")
        let reporter = try await run(ResizeCommand.self, ["-i", landscape, "-o", out, "--width", "160", "--fit", "inside"])

        let result = try await metadata(out)
        #expect((result.width, result.height) == (160, 100))
        #expect(reporter.value("Size", in: "Result") == "160x100")
    }

    @Test func cropRotateAndTextWriteTheirResults() async throws {
        defer { scratch.remove() }
        let cropped = scratch.path("crop.png")
        try await run(CropCommand.self, ["-i", landscape, "-o", cropped, "--left", "10", "--top", "20", "--width", "50", "--height", "40"])
        let cropMetadata = try await metadata(cropped)
        #expect((cropMetadata.width, cropMetadata.height) == (50, 40))

        let turned = scratch.path("turned.png")
        try await run(RotateCommand.self, ["-i", landscape, "-o", turned, "--angle", "90"])
        let turnedMetadata = try await metadata(turned)
        #expect((turnedMetadata.width, turnedMetadata.height) == (200, 320))

        // Text needs the optional Pango capability.
        if try Hokusai.capabilities().textRendering {
            let written = scratch.path("text.png")
            try await run(TextCommand.self, ["-i", landscape, "-o", written, "--text", "Hokusai", "--font-size", "24", "--x", "8", "--y", "8"])
            let textMetadata = try await metadata(written)
            #expect((textMetadata.width, textMetadata.height) == (320, 200))
        }
    }

    @Test func inspectReportsSourceMetadataNotAProcessedImage() async throws {
        let reporter = try await run(InspectCommand.self, ["-i", rotated])
        let rows = try #require(reporter.panels[rotated])

        #expect(rows.first { $0.0 == "Width" }?.1 == "120 px")
        #expect(rows.first { $0.0 == "Orientation" }?.1.contains("80×120") == true)
        #expect(reporter.panels[rotated]?.contains { $0.0 == "Embedded" } == true)
    }

    @Test func infoReportsNormalisedCapabilities() async throws {
        let reporter = try await run(InfoCommand.self, [])
        let capabilities = try Hokusai.capabilities()

        #expect(reporter.value("libvips", in: "Runtime") == capabilities.libvipsVersion)
        #expect(reporter.value("Cairo", in: "Runtime") == capabilities.cairoVersion)
        #expect(reporter.value("Output formats", in: "Runtime")?.contains("png") == true)
        #expect(reporter.value("Text rendering", in: "Runtime") == (capabilities.textRendering ? "yes" : "no"))
        #expect(reporter.value("Max evaluations", in: "Runtime") != nil)
    }

    // MARK: - Thumbnail is ordinary resize

    @Test func thumbnailOutputIsTheDocumentedAutoOrientAndResize() async throws {
        defer { scratch.remove() }
        let viaCommand = scratch.path("thumb.png")
        try await run(ThumbnailCommand.self, ["-i", rotated, "-o", viaCommand, "--width", "40", "--height", "40", "--crop", "centre"])

        let direct = try await Hokusai(url: URL(fileURLWithPath: rotated))
            .autoOrient().resize(width: 40, height: 40, fit: .cover, position: .center)
            .png().data()
        #expect(try Data(contentsOf: URL(fileURLWithPath: viaCommand)) == direct.data)
    }

    @Test func noRotateOmitsOnlyTheAutoOrient() async throws {
        defer { scratch.remove() }
        let upright = scratch.path("upright.png")
        let stored = scratch.path("stored.png")
        try await run(ThumbnailCommand.self, ["-i", rotated, "-o", upright, "--width", "60"])
        try await run(ThumbnailCommand.self, ["-i", rotated, "-o", stored, "--width", "60", "--no-rotate"])

        let uprightMetadata = try await metadata(upright)
        let storedMetadata = try await metadata(stored)
        // 120×80 stored; auto-orient displays it 80×120, so a 60-wide fit is 60×90 vs 60×40.
        #expect((uprightMetadata.width, uprightMetadata.height) == (60, 90))
        #expect((storedMetadata.width, storedMetadata.height) == (60, 40))
    }

    // MARK: - Convert

    @Test func convertSupportsTheModernEncoderSet() async throws {
        defer { scratch.remove() }
        let capabilities = try Hokusai.capabilities()
        for (name, format) in [("a.png", ImageFormat.png), ("a.webp", .webp), ("a.tif", .tiff), ("a.pdf", .pdf)]
        where capabilities.canEncode(format) {
            let out = scratch.path(name)
            try await run(ConvertCommand.self, ["-i", landscape, "-o", out])
            #expect(FileManager.default.fileExists(atPath: out), "\(name)")
        }
        let tiff = try await metadata(scratch.path("a.tif"))
        #expect(tiff.format == .tiff)
    }

    @Test func anExplicitFormatNeverRewritesTheFilename() async throws {
        defer { scratch.remove() }
        let out = scratch.path("photo.jpg")
        let message = await failureMessage(of: ConvertCommand.self, ["-i", landscape, "-o", out, "--format", "webp"])

        #expect(message?.contains("conflicts") == true)
        #expect(!FileManager.default.fileExists(atPath: out))
    }

    @Test func noMetadataFlagUsesTheLibraryDefaultAndStripRemovesEverything() async throws {
        defer { scratch.remove() }
        let defaulted = scratch.path("default.jpg")
        let stripped = scratch.path("stripped.jpg")
        try await run(ConvertCommand.self, ["-i", rich, "-o", defaulted])
        try await run(ConvertCommand.self, ["-i", rich, "-o", stripped, "--strip-metadata"])

        let libraryDefault = try await Hokusai(url: URL(fileURLWithPath: rich)).jpeg().data()
        #expect(try Data(contentsOf: URL(fileURLWithPath: defaulted)) == libraryDefault.data)

        let kept = try await metadata(defaulted)
        #expect(kept.xmp == nil && kept.iptc == nil)
        #expect(kept.iccProfile != nil)

        let removed = try await metadata(stripped)
        #expect(removed.exif == nil && removed.xmp == nil && removed.iptc == nil && removed.iccProfile == nil)
    }

    @Test func qualityIsPassedThroughToTheEncoder() async throws {
        defer { scratch.remove() }
        let low = scratch.path("low.jpg")
        let high = scratch.path("high.jpg")
        try await run(ConvertCommand.self, ["-i", landscape, "-o", low, "--quality", "5"])
        try await run(ConvertCommand.self, ["-i", landscape, "-o", high, "--quality", "95"])
        let sizes = try [low, high].map { try Data(contentsOf: URL(fileURLWithPath: $0)).count }
        #expect(sizes[0] < sizes[1])
    }

    // MARK: - Failures

    @Test func rangesAreRejectedByHokusaiAndNamedForTheOperator() async throws {
        defer { scratch.remove() }
        let width = await failureMessage(of: ResizeCommand.self, ["-i", landscape, "-o", scratch.path("a.png"), "--width", "0"])
        #expect(width?.contains("width") == true)

        let quality = await failureMessage(of: ConvertCommand.self, ["-i", landscape, "-o", scratch.path("a.jpg"), "--quality", "500"])
        #expect(quality?.contains("quality") == true)
    }

    @Test func aMissingInputIsAReadFailure() async throws {
        defer { scratch.remove() }
        let message = await failureMessage(of: ResizeCommand.self, ["-i", scratch.path("missing.jpg"), "-o", scratch.path("a.png"), "--width", "10"])
        #expect(message?.contains("missing.jpg") == true)
    }

    @Test func anEncoderTheBuildLacksIsAClearUnsupportedDiagnostic() async throws {
        defer { scratch.remove() }
        let capabilities = try Hokusai.capabilities()
        guard let missing = [ImageFormat.heif, .avif, .gif].first(where: { !capabilities.canEncode($0) }) else {
            return   // every optional encoder is present in this build
        }
        let message = await failureMessage(of: ConvertCommand.self, ["-i", landscape, "-o", scratch.path("a.out"), "--format", missing.rawValue])
        #expect(message?.contains("hokusai info") == true)
    }
}
