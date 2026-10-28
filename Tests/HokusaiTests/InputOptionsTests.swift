import Foundation
import Testing
import CVips
@testable import Hokusai

/// The single encoded-input policy (#21). Assertions check error cases and
/// Hokusai-owned fields; native diagnostic text is never a contract.
@Suite struct InputOptionsTests {
    init() throws { try Hokusai.initialize() }

    // MARK: - Helpers

    private func fixture(_ name: String, _ ext: String) throws -> URL {
        try fixtureURL(named: name, ext: ext)
    }

    /// Runs an async body and returns the error it threw, if any.
    private func terminalError(_ body: () async throws -> Output) async -> Error? {
        do {
            _ = try await body()
            return nil
        } catch {
            return error
        }
    }

    /// The first byte of the first pixel of a lowered pipeline.
    private func firstSample(of pipeline: Hokusai) throws -> UInt8 {
        let image = try Evaluator.lower(pipeline.plan, context: EvaluationContext())
        var size = 0
        guard let memory = vips_image_write_to_memory(image.pointer, &size) else {
            throw HokusaiError.runtime(FailureContext(operation: "test", reason: "no pixels"))
        }
        defer { g_free(memory) }
        return memory.load(as: UInt8.self)
    }

    // MARK: - Defaults and validation

    @Test func defaultsAreDocumentedAndCentralised() {
        let options = InputOptions()
        #expect(options.access == .random)
        #expect(options.failOn == .warning)
        #expect(options.page == nil)
        #expect(!options.revalidate)
        #expect(options.limits.maxBytes == InputLimits.defaultMaxBytes)
        #expect(options.limits.maxPixels == InputLimits.defaultMaxPixels)
        #expect(options.limits.maxChannels == InputLimits.defaultMaxChannels)
    }

    @Test func invalidOptionsFailBeforeAnySourceIsTouched() throws {
        let data = try loadFixtureData(named: "pixel", ext: "png")
        let cases: [(InputOptions, String)] = [
            (InputOptions(page: -1), "page"),
            (InputOptions(limits: InputLimits(maxBytes: 0)), "limits.maxBytes"),
            (InputOptions(limits: InputLimits(maxPixels: 0)), "limits.maxPixels"),
            (InputOptions(limits: InputLimits(maxChannels: 0)), "limits.maxChannels"),
        ]
        for (options, field) in cases {
            for make in [{ try Hokusai(data: data, options: options) }, { try Hokusai(url: URL(fileURLWithPath: "/nonexistent.png"), options: options) }] {
                do {
                    _ = try make()
                    Issue.record("expected \(field) to be rejected")
                } catch HokusaiError.invalidOption(let name, _) {
                    #expect(name == field)
                } catch {
                    Issue.record("unexpected error \(error)")
                }
            }
        }
    }

    // MARK: - Decoder failure policy

    @Test(arguments: [InputOptions.DecodeFailureLevel.none, .truncated, .error, .warning])
    func failureLevelsAreAppliedToTruncatedJPEG(level: InputOptions.DecodeFailureLevel) async throws {
        let data = try loadFixtureData(named: "truncated", ext: "jpg")
        let pipeline = try Hokusai(data: data, options: InputOptions(failOn: level)).png()
        let error = await terminalError { try await pipeline.data() }

        if level == .none {
            #expect(error == nil, "a permissive policy decodes what it can")
        } else {
            guard case HokusaiError.decode(let context)? = error else {
                Issue.record("expected decode at \(level), got \(String(describing: error))")
                return
            }
            #expect(context.operation == "decode input data")
        }
    }

    @Test(arguments: [InputOptions.DecodeFailureLevel.none, .truncated, .error, .warning])
    func failureLevelsAreAppliedToBadChecksumPNG(level: InputOptions.DecodeFailureLevel) async throws {
        let data = try loadFixtureData(named: "corrupt-crc", ext: "png")
        let pipeline = try Hokusai(data: data, options: InputOptions(failOn: level)).png()
        let error = await terminalError { try await pipeline.data() }

        switch level {
        case .none, .truncated:
            #expect(error == nil)
        case .error, .warning:
            guard case HokusaiError.decode? = error else {
                Issue.record("expected decode at \(level), got \(String(describing: error))")
                return
            }
        }
    }

    @Test func defaultPolicyIsActuallyApplied() async throws {
        let data = try loadFixtureData(named: "truncated", ext: "jpg")
        let error = await terminalError { try await Hokusai(data: data).png().data() }
        guard case HokusaiError.decode? = error else {
            Issue.record("the declared .warning default must reject a truncated image, got \(String(describing: error))")
            return
        }
    }

    @Test func decodeFailureInsideAFilePipelineIsLabelledWithTheFile() async throws {
        let url = try fixture("truncated", "jpg")
        let error = await terminalError { try await Hokusai(url: url).resize(width: 50).png().data() }
        guard case HokusaiError.decode(let context)? = error else {
            Issue.record("expected decode, got \(String(describing: error))")
            return
        }
        #expect(context.operation == "decode truncated.jpg")
    }

    @Test func decodeFailureInACompositeLayerNamesTheLayer() async throws {
        let base = try Hokusai(url: fixture("landscape-asym", "jpg"))
        let broken = try Hokusai(url: fixture("truncated", "jpg"))
        let error = await terminalError { try await base.composite([CompositeLayer(broken)]).png().data() }
        guard case HokusaiError.decode(let context)? = error else {
            Issue.record("expected decode, got \(String(describing: error))")
            return
        }
        #expect(context.operation == "composite layer 1 / decode truncated.jpg")
    }

    // MARK: - Access mode

    @Test func sequentialAccessSupportsSinglePassPipelines() async throws {
        let data = try loadFixtureData(named: "landscape-asym", ext: "jpg")
        let sequential = try await Hokusai(data: data, options: .sequential).resize(width: 64).png().data()
        let random = try await Hokusai(data: data).resize(width: 64).png().data()
        #expect(sequential.info == random.info)
    }

    @Test func sourceReadFailuresExplainSequentialAccessOnlyWhenItWasUsed() async throws {
        // Streaming access can also fail on out-of-order reads, which looks
        // like a source failure from the outside, so the reason says so. Random
        // access has no such ambiguity.
        let data = try loadFixtureData(named: "truncated", ext: "jpg")

        for (options, mentionsSequential) in [(InputOptions.sequential, true), (InputOptions(), false)] {
            let error = await terminalError { try await Hokusai(data: data, options: options).png().data() }
            guard case HokusaiError.decode(let context)? = error else {
                Issue.record("expected decode, got \(String(describing: error))")
                continue
            }
            #expect(context.reason.contains("sequential") == mentionsSequential)
        }
    }

    // MARK: - Page selection

    @Test func singlePageSelectionLoadsTheRequestedPage() throws {
        let url = try fixture("multipage", "tif")
        let levels = try (0..<3).map { page in
            try firstSample(of: Hokusai(url: url, options: InputOptions(page: page)))
        }
        #expect(levels == [30, 120, 210])
        #expect(try firstSample(of: Hokusai(url: url)) == 30, "no page means the first page")

        let data = try Data(contentsOf: url)
        #expect(try firstSample(of: Hokusai(data: data, options: InputOptions(page: 2))) == 210)
    }

    @Test func selectedPageIsExactlyOneImage() async throws {
        let url = try fixture("multipage", "tif")
        let output = try await Hokusai(url: url, options: InputOptions(page: 1)).png().data()
        #expect(output.info.width == 16)
        #expect(output.info.height == 16)
    }

    @Test func outOfRangePageIsAnInvalidOption() async throws {
        let url = try fixture("multipage", "tif")
        let error = await terminalError { try await Hokusai(url: url, options: InputOptions(page: 3)).png().data() }
        guard case HokusaiError.invalidOption(let name, _)? = error else {
            Issue.record("expected invalidOption, got \(String(describing: error))")
            return
        }
        #expect(name == "page")
    }

    @Test func pageSelectionOnASinglePageFormatIsUnsupportedExceptPageZero() async throws {
        let data = try loadFixtureData(named: "landscape-asym", ext: "jpg")

        let first = try await Hokusai(data: data, options: InputOptions(page: 0)).png().data()
        #expect(first.info.width == 320)

        let error = await terminalError { try await Hokusai(data: data, options: InputOptions(page: 1)).png().data() }
        guard case HokusaiError.unsupported(let feature, _)? = error else {
            Issue.record("expected unsupported, got \(String(describing: error))")
            return
        }
        #expect(feature == "page selection")
    }

    // MARK: - Limits

    @Test func oversizedDataIsRejectedBeforeAnyNativeCopy() throws {
        let data = try loadFixtureData(named: "landscape-asym", ext: "jpg")
        do {
            _ = try Hokusai(data: data, options: InputOptions(limits: InputLimits(maxBytes: 1000)))
            Issue.record("expected the byte limit to reject the data")
        } catch HokusaiError.resource(let failure) {
            #expect(failure.kind == .encodedBytes)
            #expect(failure.limit == 1000)
            #expect(failure.actual == data.count)
        }
    }

    @Test func oversizedFileIsRejectedWhenItIsOpened() async throws {
        let url = try fixture("landscape-asym", "jpg")
        let pipeline = try Hokusai(url: url, options: InputOptions(limits: InputLimits(maxBytes: 1000))).png()
        let error = await terminalError { try await pipeline.data() }
        guard case HokusaiError.resource(let failure)? = error else {
            Issue.record("expected resource, got \(String(describing: error))")
            return
        }
        #expect(failure.kind == .encodedBytes)
        #expect(failure.limit == 1000)
    }

    @Test func pixelLimitIsCheckedAfterTheHeaderLoadsAndBeforeEvaluation() async throws {
        let data = try loadFixtureData(named: "landscape-asym", ext: "jpg")
        let pipeline = try Hokusai(data: data, options: InputOptions(limits: InputLimits(maxPixels: 1000)))

        for check in [{ _ = try await pipeline.metadata() }, { _ = try await pipeline.png().data() }] as [() async throws -> Void] {
            do {
                try await check()
                Issue.record("expected the pixel limit to reject the image")
            } catch HokusaiError.resource(let failure) {
                #expect(failure.kind == .decodedPixels)
                #expect(failure.limit == 1000)
                #expect(failure.actual == 320 * 200)
            }
        }
    }

    @Test func channelLimitIsEnforced() async throws {
        let data = try loadFixtureData(named: "pixel", ext: "png")
        let pipeline = try Hokusai(data: data, options: InputOptions(limits: InputLimits(maxChannels: 1))).png()
        let error = await terminalError { try await pipeline.data() }
        guard case HokusaiError.resource(let failure)? = error else {
            Issue.record("expected resource, got \(String(describing: error))")
            return
        }
        #expect(failure.kind == .channels)
        #expect(failure.limit == 1)
        #expect(failure.actual == 2)
    }

    @Test func pixelCountOverflowIsRejectedNotWrapped() {
        let limits = InputLimits()
        do {
            try limits.checkDecoded(width: Int.max, height: 2, channels: 1)
            Issue.record("expected overflow to be rejected")
        } catch HokusaiError.resource(let failure) {
            #expect(failure.kind == .decodedPixels)
            #expect(failure.actual == nil)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func imagesAtTheLimitAreAccepted() async throws {
        let data = try loadFixtureData(named: "landscape-asym", ext: "jpg")
        let limits = InputLimits(maxBytes: data.count, maxPixels: 320 * 200, maxChannels: 3)
        let output = try await Hokusai(data: data, options: InputOptions(limits: limits)).png().data()
        #expect(output.info.width == 320)
    }

    // MARK: - File freshness

    @Test func revalidateSeesAFileReplacedAtTheSamePath() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hokusai-revalidate-\(UUID().uuidString).img")
        defer { try? FileManager.default.removeItem(at: url) }

        try loadFixtureData(named: "pixel", ext: "png").write(to: url)
        let before = try await Hokusai(url: url).metadata()
        #expect(before.width == 1)

        try loadFixtureData(named: "landscape-asym", ext: "jpg").write(to: url)
        let after = try await Hokusai(url: url, options: InputOptions(revalidate: true)).metadata()
        #expect(after.width == 320)
    }

    // MARK: - Ownership and concurrency

    @Test func dataSourceSurvivesMutationOfTheOriginal() async throws {
        var data = try loadFixtureData(named: "landscape-asym", ext: "jpg")
        let pipeline = try Hokusai(data: data, options: InputOptions(access: .sequential)).resize(width: 64).png()

        data.resetBytes(in: 0..<data.count)
        data = Data()

        #expect(try await pipeline.data().info.width == 64)
    }

    @Test func concurrentInputCreationAndEvaluationIsSafe() async throws {
        let jpeg = try loadFixtureData(named: "landscape-asym", ext: "jpg")
        let tiff = try fixture("multipage", "tif")

        try await withThrowingTaskGroup(of: Int.self) { group in
            for index in 0..<48 {
                group.addTask {
                    switch index % 3 {
                    case 0: return try await Hokusai(data: jpeg).resize(width: 32).png().data().info.width
                    case 1: return try await Hokusai(url: tiff, options: InputOptions(page: index % 3 + (index / 3) % 2)).png().data().info.width
                    default: return try await Hokusai(data: jpeg, options: .sequential).resize(width: 32).png().data().info.width
                    }
                }
            }
            for try await width in group {
                #expect(width == 32 || width == 16)
            }
        }
    }
}
