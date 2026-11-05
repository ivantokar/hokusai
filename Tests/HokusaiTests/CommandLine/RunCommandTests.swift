import ArgumentParser
import Foundation
@testable import Hokusai
import Testing
@testable import HokusaiCommandLine

/// `hokusai run` (#115): a pipeline written as the library writes it, parsed in order, evaluated
/// once, and checked through the public API by reading the written file back.
@Suite struct RunCommandTests {
    private let landscape: String
    private let rotated: String
    private let scratch: ScratchDirectory

    init() throws {
        landscape = try fixturePath(named: "landscape-asym", ext: "jpg")
        rotated = try fixturePath(named: "orientation-6", ext: "jpg")
        scratch = try ScratchDirectory()
    }

    private func runPipeline(_ words: [String]) async throws {
        try await RunCommand.execute(try PipelineParser.parse(words))
    }

    private func metadata(_ path: String) async throws -> ImageMetadata {
        try await Hokusai(url: URL(fileURLWithPath: path)).metadata()
    }

    private func failure(_ words: [String]) async -> String? {
        do {
            try await runPipeline(words)
            return nil
        } catch let error as CommandFailure {
            return error.message
        } catch {
            return "\(error)"
        }
    }

    @Test func aPipelineIsDecodedOnceAndWrittenInTheChosenEncoder() async throws {
        defer { scratch.remove() }
        let out = scratch.path("social.webp")
        try await runPipeline([landscape, "auto-orient", "resize", "--width", "160", "--height", "80", "blur", "--sigma", "1.5", "webp", "--quality", "70", "-o", out])
        let result = try await metadata(out)
        #expect(result.format == .webp)
        #expect((result.width, result.height) == (160, 80))
    }

    @Test func theOrderOfStepsIsTheOrderWritten() async throws {
        defer { scratch.remove() }
        let a = scratch.path("a.png"), b = scratch.path("b.png")
        // 320 x 200: resize to a 100 wide box then turn, against turn then resize to 100 wide.
        try await runPipeline([landscape, "resize", "--width", "100", "--fit", "inside", "rotate", "--degrees", "90", "-o", a])
        try await runPipeline([landscape, "rotate", "--degrees", "90", "resize", "--width", "100", "--fit", "inside", "-o", b])
        let first = try await metadata(a), second = try await metadata(b)
        #expect((first.width, first.height) == (62, 100))
        #expect((second.width, second.height) == (100, 160))
    }

    @Test func aStepOptionThatLooksLikeAStepNameIsAValue() async throws {
        defer { scratch.remove() }
        let out = scratch.path("c.tif")
        // `jpeg` is both a TIFF compression and a step name.
        try await runPipeline([landscape, "resize", "--width", "64", "tiff", "--compression", "jpeg", "-o", out])
        #expect(try await metadata(out).format == .tiff)
    }

    @Test func outputAndJSONMayStandAnywhere() async throws {
        defer { scratch.remove() }
        let out = scratch.path("d.png")
        let request = try PipelineParser.parse(["-o", out, landscape, "--json", "resize", "--width", "50"])
        #expect(request.output == out && request.json)
        #expect(request.steps.count == 1)
        try await RunCommand.execute(request)
        #expect(try await metadata(out).width == 50)
    }

    @Test func theLibraryDefaultsApply() async throws {
        defer { scratch.remove() }
        // resize defaults to cover, as in the library: a 100 x 100 box is filled, not fitted inside.
        let out = scratch.path("e.png")
        try await runPipeline([landscape, "resize", "--width", "100", "--height", "100", "-o", out])
        let result = try await metadata(out)
        #expect((result.width, result.height) == (100, 100))
        // Text defaults are TextStyle's.
        let style = try TextStyleOptions.parse([])
        #expect(style.fontSize == TextStyle().fontSize)
        #expect(style.color == TextStyle().color)
    }

    @Test func anOptionBelongsOnlyToTheStepsThatHaveIt() async throws {
        defer { scratch.remove() }
        let out = scratch.path("f.png")
        #expect(await failure([landscape, "resize", "--width", "100", "--quality", "10", "-o", out])?.contains("Unknown option '--quality'") == true)
        #expect(await failure([landscape, "png", "--quality", "10", "-o", out])?.contains("png step") == true)
        #expect(await failure([landscape, "png", "--palette-quality", "10", "-o", out])?.contains("--palette") == true)
        #expect(await failure([landscape, "resize", "-o", out])?.contains("specify --width") == true)
    }

    @Test func aMissingOutputOrStepOrEncoderIsExplained() async throws {
        defer { scratch.remove() }
        #expect(await failure([landscape, "resize", "--width", "100"])?.contains("-o <path>") == true)
        #expect(await failure([landscape, "nope", "-o", scratch.path("x.png")])?.contains("nope") == true)
        #expect(await failure([landscape, "resize", "--width", "100", "-o", "-"])?.contains("needs an encoder step") == true)
    }

    @Test func theEncoderIsTakenFromTheExtensionWhenNoStepNamesOne() async throws {
        defer { scratch.remove() }
        let out = scratch.path("g.jpg")
        try await runPipeline([landscape, "resize", "--width", "80", "-o", out])
        #expect(try await metadata(out).format == .jpeg)
    }

    @Test func inputOptionsReachTheLibrary() async throws {
        defer { scratch.remove() }
        let out = scratch.path("h.png")
        // A decode limit is the library's own typed error; `run` words it with the other failures.
        await #expect(throws: HokusaiError.self) { try await runPipeline([landscape, "--max-pixels", "10", "png", "-o", out]) }
        #expect(await failure([landscape, "--text", "x", "png", "-o", out])?.contains("exactly one") == true)
        try await runPipeline([landscape, "--fail-on", "none", "--access", "random", "resize", "--width", "40", "-o", out])
        #expect(try await metadata(out).width == 40)
    }

    @Test func aTextSourceStartsAPipeline() async throws {
        guard try Hokusai.capabilities().textRendering else { return }
        defer { scratch.remove() }
        let out = scratch.path("t.png")
        try await runPipeline(["--text", "Hokusai", "--font-size", "32", "png", "-o", out])
        let result = try await metadata(out)
        #expect(result.width > 20 && result.height > 10)
    }

    @Test func overlaysAndDrawnTextComposeInOrder() async throws {
        defer { scratch.remove() }
        let overlay = scratch.path("overlay.png"), out = scratch.path("i.png")
        try await runPipeline([landscape, "resize", "--width", "40", "--height", "40", "png", "-o", overlay])
        try await runPipeline([landscape, "composite", "--overlay", overlay, "--gravity", "south-east", "--blend", "over", "--opacity", "0.5", "png", "-o", out])
        #expect(try await metadata(out).width == 320)
        let tiled = scratch.path("tiled.png")
        try await runPipeline([landscape, "composite", "--overlay", overlay, "--tile", "png", "-o", tiled])
        #expect(try await metadata(tiled).width == 320)
        if try Hokusai.capabilities().textRendering {
            let drawn = scratch.path("drawn.png")
            try await runPipeline([landscape, "draw-text", "--text", "Hi", "--x", "8", "--y", "8", "png", "-o", drawn])
            #expect(try await metadata(drawn).height == 200)
        }
    }

    @Test func metadataPolicyIsAStep() async throws {
        defer { scratch.remove() }
        let rich = try fixturePath(named: "metadata-rich", ext: "jpg")
        let kept = scratch.path("kept.jpg"), stripped = scratch.path("stripped.jpg")
        try await runPipeline([rich, "jpeg", "metadata-policy", "--preset", "preserve-all", "-o", kept])
        try await runPipeline([rich, "jpeg", "metadata-policy", "--preset", "remove-all", "-o", stripped])
        #expect(try await metadata(kept).exif != nil)
        #expect(try await metadata(stripped).exif == nil)
    }

    @Test func everyStepIsReachableAndHasItsOwnHelp() throws {
        let names = PipelineSteps.all.map { $0.name }
        #expect(Set(names).count == names.count, "step names must be unique")
        #expect(names.count == 36)
        for name in ["auto-orient", "resize", "rotate", "flip", "flop", "extract", "extend", "affine", "trim", "smart-crop", "blur", "sharpen",
            "grayscale", "tint", "normalize", "clahe", "gamma", "negate", "median", "threshold", "modulate", "convert-to", "ensure-alpha",
            "flatten", "remove-alpha", "composite", "draw-text", "jpeg", "png", "webp", "avif", "heif", "tiff", "gif", "pdf", "metadata-policy"] {
            #expect(PipelineSteps.names.contains(name), "missing step \(name)")
        }
    }

    @Test func theJSONReportIsTheOutputInfo() throws {
        let info = OutputInfo(format: .webp, width: 3, height: 2, byteCount: 10)
        let text = try JSONText.render(info, output: "o.webp")
        let object = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(object["format"] as? String == "webp" && object["width"] as? Int == 3 && object["byteCount"] as? Int == 10)
        #expect(object["mimeType"] as? String == "image/webp")
    }
    @Test func inspectCanReportJSONAndConvertRefusesFlagsItWouldIgnore() async throws {
        let metadata = try await Hokusai(url: URL(fileURLWithPath: rotated)).metadata()
        let text = try MetadataSummary.json(for: metadata, input: rotated)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(object["format"] as? String == "jpeg" && object["orientedWidth"] as? Int == 80)

        // `convert --quality` to PNG used to succeed without applying anything.
        let out = scratch.path("never.png")
        defer { scratch.remove() }
        await #expect(throws: (any Error).self) { try await run(ConvertCommand.self, ["-i", landscape, "-o", out, "--quality", "30"]) }
        #expect(!FileManager.default.fileExists(atPath: out))
        #expect(EncoderFactory.ignoredFlags(for: .jpeg, settings: EncoderSettings(quality: 30, progressive: true)).isEmpty)
        #expect(EncoderFactory.ignoredFlags(for: .jpeg, settings: EncoderSettings(effort: 4, lossless: true)) == ["--effort", "--lossless"])
        #expect(EncoderFactory.ignoredFlags(for: .pdf, settings: EncoderSettings(quality: 1)) == ["--quality"])
    }
}
