import Foundation
import Testing
@testable import Hokusai

/// Immutable plan and terminal-evaluator contract (#34).
@Suite struct ImagePlanTests {
    init() throws { try Hokusai.initialize() }

    private func operationNames(_ pipeline: Hokusai) -> [String] {
        pipeline.plan.linearized.operations.map(\.name)
    }

    @Test func chainingPreservesExactOperationOrder() async throws {
        let input = try loadFixtureData(named: "landscape-asym", ext: "jpg")
        let resizeThenExtract = try Hokusai(data: input)
            .resize(width: 160)
            .extract(x: 0, y: 0, width: 100, height: 100)
        let extractThenResize = try Hokusai(data: input)
            .extract(x: 0, y: 0, width: 100, height: 100)
            .resize(width: 160)

        #expect(operationNames(resizeThenExtract) == ["resize", "extract"])
        #expect(operationNames(extractThenResize) == ["extract", "resize"])

        let first = try await resizeThenExtract.png().data().info
        let second = try await extractThenResize.png().data().info
        #expect((first.width, first.height) == (100, 100))
        #expect((second.width, second.height) == (160, 160))
    }

    @Test func branchingLeavesTheBasePipelineUnchanged() throws {
        let base = try Hokusai(data: loadFixtureData(named: "pixel", ext: "png")).autoOrient()
        let thumb = try base.resize(width: 30).jpeg()
        let hero = try base.blur(sigma: 2).webp()

        #expect(operationNames(base) == ["auto orient"])
        #expect(base.terminal.encoder == nil)
        #expect(operationNames(thumb) == ["auto orient", "resize"])
        #expect(operationNames(hero) == ["auto orient", "blur"])
    }

    @Test func constructionAndConfigurationDoNoNativeWork() async throws {
        // Invalid image bytes can only be detected by decoding, so reaching
        // the terminal proves nothing before it opened the source.
        let configured = try Hokusai(data: Data("not an image".utf8))
            .resize(width: 10)
            .blur()
            .webp(quality: 80)
            .preserveMetadata()

        await #expect {
            try await configured.data()
        } throws: { error in
            guard case HokusaiError.decode(let context) = error else { return false }
            return context.operation == "decode input data"
        }
    }

    @Test func missingFileIsReportedByTheTerminal() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("missing-\(UUID().uuidString).jpg")
        let pipeline = try Hokusai(url: url).jpeg()

        await #expect {
            try await pipeline.data()
        } throws: { error in
            guard case HokusaiError.io(_, let operation, _) = error else { return false }
            return operation == .read
        }
    }

    @Test func pixelDependentValidationRunsAtEvaluation() async throws {
        let input = try loadFixtureData(named: "landscape-asym", ext: "jpg")
        let shrinking = try Hokusai(data: input).extend(to: ImageSize(width: 10, height: 10)).png()

        await #expect {
            try await shrinking.data()
        } throws: { error in
            guard case HokusaiError.invalidOption(let name, _) = error else { return false }
            return name == "size"
        }
    }

    @Test func dataAndWriteShareEvaluatorSemantics() async throws {
        let input = try loadFixtureData(named: "landscape-asym", ext: "jpg")
        let pipeline = try Hokusai(data: input)
            .resize(width: 120, height: 90, fit: .cover)
            .png()
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hokusai-plan-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        let output = try await pipeline.data()
        let info = try await pipeline.write(to: url)

        #expect(info == output.info)
        #expect(try Data(contentsOf: url) == output.data)
    }

    @Test func compositeLayerContributesOnlyItsImagePlan() async throws {
        let base = try Hokusai(data: loadFixtureData(named: "landscape-asym", ext: "jpg"))
        let logo = try Hokusai(data: loadFixtureData(named: "pixel", ext: "png")).resize(width: 20, fit: .fill)

        let plain = try await base.composite([CompositeLayer(logo, x: 4, y: 4)]).png().data()
        let configured = try await base
            .composite([CompositeLayer(logo.avif(quality: 1).preserveMetadata(), x: 4, y: 4)])
            .png()
            .data()

        #expect(configured.data == plain.data)
    }

    @Test func dataSourceSurvivesCallerMutationBeforeEvaluation() async throws {
        var input = try loadFixtureData(named: "landscape-asym", ext: "jpg")
        let pipeline = try Hokusai(data: input).resize(width: 64).jpeg()

        input.resetBytes(in: 0..<input.count)
        input = Data()

        let output = try await pipeline.data()
        #expect(output.info.width == 64)
    }
}
