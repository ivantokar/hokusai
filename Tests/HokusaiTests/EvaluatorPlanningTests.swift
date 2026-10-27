import Foundation
import Testing
@testable import Hokusai

/// Semantics-preserving planning rules (#39). The planner is exercised as a
/// pure function, then through real evaluations compared with the reference
/// lowering (every optimisation off).
@Suite struct EvaluatorPlanningTests {
    init() throws { try Hokusai.initialize() }

    // MARK: - Helpers

    private func base() throws -> Hokusai {
        try Hokusai(data: loadFixtureData(named: "landscape-asym", ext: "jpg"))
    }

    private func logo() throws -> Hokusai {
        try Hokusai(data: loadFixtureData(named: "pixel", ext: "png")).resize(width: 24, fit: .fill)
    }

    /// Evaluates synchronously with an explicit planner and returns the trace.
    private func run(
        _ pipeline: Hokusai,
        planner: PlannerOptions = .default
    ) throws -> (output: Output, events: [PlanTrace.Event]) {
        let trace = PlanTrace()
        let context = EvaluationContext(planner: planner, trace: trace)
        let output = try Evaluator.encode(
            pipeline.plan, pipeline.terminal, as: pipeline.terminal.encoder ?? .png(), context: context)
        return (output, trace.events)
    }

    private func lowered(_ events: [PlanTrace.Event]) -> [String] {
        events.compactMap { if case .operationLowered(let name) = $0 { name } else { nil } }
    }

    private func opened(_ events: [PlanTrace.Event]) -> [String] {
        events.compactMap { if case .sourceOpened(let label) = $0 { label } else { nil } }
    }

    private func hits(_ events: [PlanTrace.Event]) -> Int {
        events.filter { if case .memoisationHit = $0 { true } else { false } }.count
    }

    // MARK: - The planner as a pure function

    @Test func planningNeverReordersOrDropsWrittenOperations() throws {
        let image = try base()
        let pipelines = [
            try image.autoOrient().resize(width: 100).blur().extract(x: 0, y: 0, width: 50, height: 50),
            try image.rotate(by: 360).resize(width: 100).composite([]).rotate(by: 90).sharpen(),
            try image.trim().blur().trim().grayscale(),
            try image.blur().resize(width: 50).blur(),
        ]
        for pipeline in pipelines {
            let written = pipeline.plan.linearized.operations
            let planned = Planner.plan(written, options: .default)
            #expect(planned.map(\.operation.name) == written.map(\.name))
        }
    }

    @Test(arguments: [0.0, 360.0, -360.0, 720.0, 1080.0])
    func wholeTurnsAreIdentityRotations(degrees: Double) {
        let steps = Planner.plan([.rotate(degrees: degrees, background: .transparent)], options: .default)
        #expect(steps[0].skippedBy == .identityRotation)
    }

    @Test(arguments: [90.0, 180.0, 270.0, -90.0, 0.5, 359.999, 360.001, 45.0])
    func partialTurnsAreNeverSkipped(degrees: Double) {
        let steps = Planner.plan([.rotate(degrees: degrees, background: .transparent)], options: .default)
        #expect(steps[0].skippedBy == nil)
    }

    @Test func onlyAnEmptyCompositeIsAnIdentity() throws {
        let layer = LayerStep(plan: try logo().plan, x: 0, y: 0, blend: .over, opacity: 1)
        let steps = Planner.plan([.composite([]), .composite([layer])], options: .default)
        #expect(steps[0].skippedBy == .emptyComposite)
        #expect(steps[1].skippedBy == nil)
    }

    @Test func lookalikeIdentitiesAreNotAssumed() throws {
        // Each of these can look unchanged yet carries a resampling,
        // interpretation, or blend contract, so none may be skipped.
        let steps = Planner.plan([
            .resize(ResizeStep(width: 320, height: 200, fit: .fill, position: .center, kernel: .lanczos3,
                               withoutEnlargement: false, withoutReduction: false, background: .transparent)),
            .convertToSRGB,
            .extend(to: ImageSize(width: 320, height: 200), anchor: .center, mode: .background(.transparent)),
            .flip,
            .blur(sigma: 0.0001),
        ], options: .default)
        #expect(steps.allSatisfy { $0.skippedBy == nil })
    }

    @Test func disabledRulesAreHonoured() {
        let written: [ImageOperation] = [.rotate(degrees: 360, background: .transparent), .composite([])]
        #expect(Planner.plan(written, options: .reference).allSatisfy { $0.skippedBy == nil })
        #expect(Planner.plan(written, options: PlannerOptions(disabled: [.identityRotation])).map(\.skippedBy) == [nil, .emptyComposite])
    }

    // MARK: - Lowering order and no-op rules on real pipelines

    @Test func loweringTraceFollowsWrittenOrder() throws {
        let pipeline = try base().autoOrient().resize(width: 100).blur().extract(x: 0, y: 0, width: 40, height: 40).png()
        let events = try run(pipeline).events

        #expect(opened(events) == ["decode input data"])
        #expect(lowered(events) == ["auto orient", "resize", "blur", "extract"])
        #expect(events.first == .sourceOpened("decode input data"))
    }

    @Test func operationsBeforeAResizeStayBeforeIt() throws {
        let events = try run(base().blur(sigma: 2).resize(width: 100).png()).events
        #expect(lowered(events) == ["blur", "resize"])
    }

    @Test func analyticalOperationsKeepTheirPosition() throws {
        let image = try base()
        let trimThenBlur = try run(image.trim().blur(sigma: 3).png())
        let blurThenTrim = try run(image.blur(sigma: 3).trim().png())
        #expect(lowered(trimThenBlur.events) == ["trim", "blur"])
        #expect(lowered(blurThenTrim.events) == ["blur", "trim"])

        // This fixture has nothing for `trim` to remove, so the observable
        // consequence of reordering is shown with a pair that does not commute.
        let blurThenResize = try run(image.blur(sigma: 3).resize(width: 50).png())
        let resizeThenBlur = try run(image.resize(width: 50).blur(sigma: 3).png())
        #expect(lowered(blurThenResize.events) == ["blur", "resize"])
        #expect(lowered(resizeThenBlur.events) == ["resize", "blur"])
        #expect(blurThenResize.output.data != resizeThenBlur.output.data)
    }

    @Test func identityRulesSkipWithoutChangingTheResult() throws {
        let pipeline = try base().rotate(by: 360).resize(width: 120).composite([]).blur().png()

        let optimised = try run(pipeline)
        let reference = try run(pipeline, planner: .reference)

        #expect(optimised.events.contains(.operationSkipped("rotate", .identityRotation)))
        #expect(optimised.events.contains(.operationSkipped("composite layer", .emptyComposite)))
        #expect(lowered(optimised.events) == ["resize", "blur"])
        #expect(lowered(reference.events) == ["rotate", "resize", "composite layer", "blur"])

        #expect(optimised.output.info == reference.output.info)
        #expect(optimised.output.data == reference.output.data)
    }

    @Test func partialRotationIsStillAppliedAndOutputMatchesReference() throws {
        let pipeline = try base().rotate(by: 90).png()
        let optimised = try run(pipeline)
        #expect(lowered(optimised.events) == ["rotate"])
        #expect(optimised.output.info.width == 200)
        let reference = try run(pipeline, planner: .reference)
        #expect(optimised.output.data == reference.output.data)
    }

    // MARK: - Per-evaluation memoisation

    @Test func aSharedLayerIsBuiltOncePerEvaluation() throws {
        let sharedLogo = try logo()
        let pipeline = try base()
            .composite([CompositeLayer(sharedLogo, x: 4, y: 4), CompositeLayer(sharedLogo, x: 60, y: 60)])
            .png()

        let optimised = try run(pipeline)
        let reference = try run(pipeline, planner: .reference)

        #expect(opened(optimised.events).count == 2, "the base once and the logo once")
        #expect(hits(optimised.events) >= 1)
        #expect(opened(reference.events).count == 3, "without memoisation the logo opens per layer")
        #expect(hits(reference.events) == 0)
        #expect(optimised.output.data == reference.output.data)
    }

    @Test func aLayerDerivedFromTheBaseSharesItsSource() throws {
        let image = try base()
        let pipeline = try image.composite([CompositeLayer(image.resize(width: 80), x: 10, y: 10)]).png()

        let optimised = try run(pipeline)
        let reference = try run(pipeline, planner: .reference)

        #expect(opened(optimised.events).count == 1)
        #expect(opened(reference.events).count == 2)
        #expect(optimised.output.data == reference.output.data)
    }

    @Test func independentValuesAreNeverDeduplicated() throws {
        // Equal bytes in separate Hokusai values are separate plans: sharing is
        // by node identity, never by structural equality.
        let first = try Hokusai(data: loadFixtureData(named: "pixel", ext: "png"))
        let second = try Hokusai(data: loadFixtureData(named: "pixel", ext: "png"))
        let pipeline = try base().composite([CompositeLayer(first), CompositeLayer(second)]).png()

        let events = try run(pipeline).events
        #expect(opened(events).count == 3)
        #expect(hits(events) == 0)
    }

    @Test func sequentialSourcesAreNeverShared() throws {
        let streaming = try Hokusai(data: loadFixtureData(named: "pixel", ext: "png"), options: .sequential)
        let pipeline = try base().composite([CompositeLayer(streaming), CompositeLayer(streaming, x: 8)]).png()

        let trace = PlanTrace()
        _ = try Evaluator.lower(pipeline.plan, context: EvaluationContext(trace: trace))
        #expect(opened(trace.events).count == 3, "each reader gets its own forward-only stream")
        #expect(hits(trace.events) == 0)
    }

    @Test func evaluationsDoNotShareAHiddenResultCache() throws {
        let pipeline = try base().resize(width: 64).png()
        let first = try run(pipeline).events
        let second = try run(pipeline).events

        #expect(opened(first) == opened(second))
        #expect(opened(second).count == 1)
        #expect(hits(second) == 0)
    }

    @Test func memoisationDoesNotChangeFailureReporting() throws {
        let broken = try Hokusai(data: loadFixtureData(named: "truncated", ext: "jpg")).resize(width: 20)
        let pipeline = try base().composite([CompositeLayer(broken), CompositeLayer(broken)]).png()

        do {
            _ = try run(pipeline)
            Issue.record("expected the truncated layer to fail")
        } catch HokusaiError.decode(let context) {
            #expect(context.operation == "composite layer 1 / decode truncated.jpg" || context.operation == "composite layer 1 / decode input data")
        }
    }

    // MARK: - Terminals

    @Test func lastTerminalConfigurationWins() async throws {
        let image = try base().resize(width: 40)
        let reconfigured = try image.png().webp(quality: 70).metadataPolicy(.preserveAll).metadataPolicy(.default)

        #expect(reconfigured.terminal.metadataPolicy == .default)
        if case .webp(let options)? = reconfigured.terminal.encoder {
            #expect(options.quality == 70)
        } else {
            Issue.record("expected the last encoder to win")
        }
        let output = try await reconfigured.data()
        #expect(output.info.format == .webp)
    }

    @Test func terminalChoiceDoesNotChangeThePlan() throws {
        let image = try base().resize(width: 40)
        let names = { (pipeline: Hokusai) in pipeline.plan.linearized.operations.map(\.name) }
        let png = try names(image.png())
        let webp = try names(image.webp())
        let jpeg = try names(image.jpeg())
        #expect(png == webp)
        #expect(jpeg == names(image))
    }

    @Test func fileTerminalsUseADirectSink() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        func sink(_ pipeline: Hokusai, to name: String) throws -> [PlanTrace.Event] {
            let url = directory.appendingPathComponent("hokusai-plan-\(UUID().uuidString)-\(name)")
            defer { try? FileManager.default.removeItem(at: url) }
            let trace = PlanTrace()
            _ = try Evaluator.write(
                pipeline.plan, pipeline.terminal, as: pipeline.terminal.encoder ?? .png(), to: url,
                context: EvaluationContext(trace: trace))
            return trace.events.filter { if case .sinkSelected = $0 { true } else { false } }
        }

        let image = try base().resize(width: 40)
        let png = try sink(image.png(), to: "a.png")
        let webp = try sink(image.webp(), to: "a.webp")
        let pdf = try sink(image.pdf(), to: "a.pdf")
        let memory = try run(image.png()).events
        #expect(png == [.sinkSelected("file png")])
        #expect(webp == [.sinkSelected("file webp")])
        #expect(pdf == [.sinkSelected("file pdf")])
        #expect(memory.contains(.sinkSelected("memory png")))
    }
}
