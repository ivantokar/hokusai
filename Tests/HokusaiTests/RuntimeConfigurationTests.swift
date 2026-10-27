import CVips
import Foundation
import Testing
@testable import Hokusai

/// Process-level configuration, capabilities, and status (#28).
@Suite struct RuntimeConfigurationTests {
    init() throws { try Hokusai.initialize() }

    // MARK: - Configuration

    @Test func invalidConfigurationIsRejectedBeforeAnyStateCheck() {
        let invalid: [(RuntimeConfiguration, String)] = [
            (.init(maxConcurrentEvaluations: .fixed(0)), "maxConcurrentEvaluations"),
            (.init(maxQueuedEvaluations: -1), "maxQueuedEvaluations"),
            (.init(vipsConcurrency: .fixed(0)), "vipsConcurrency"),
            (.init(vipsConcurrency: .fixed(Int(Int32.max) + 1)), "vipsConcurrency"),
        ]
        for (configuration, field) in invalid {
            do {
                try Hokusai.configure(configuration)
                Issue.record("expected \(field) to be rejected")
            } catch HokusaiError.invalidOption(let name, _) {
                #expect(name == field)
            } catch {
                Issue.record("unexpected error \(error)")
            }
        }
    }

    @Test func configurationIsFrozenAfterFirstUse() {
        #expect(Hokusai.runtimeStatus.isConfigurationFrozen)
        do {
            try Hokusai.configure(.init(maxConcurrentEvaluations: .fixed(2)))
            Issue.record("expected frozen configuration to be rejected")
        } catch HokusaiError.runtime(let context) {
            #expect(context.operation == "configure")
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func configurationStateAllowsOneConfigureBeforeFreeze() throws {
        var state = ConfigurationState()
        let requested = RuntimeConfiguration(maxConcurrentEvaluations: .fixed(3), maxQueuedEvaluations: 8, vipsConcurrency: .fixed(2))

        #expect(state.effective == RuntimeConfiguration())
        try state.configure(requested)
        #expect(!state.isFrozen)
        #expect(state.effective == requested)
        #expect(throws: HokusaiError.self) { try state.configure(requested) }

        #expect(state.freeze() == requested)
        #expect(state.isFrozen)
        #expect(throws: HokusaiError.self) { try state.configure(RuntimeConfiguration()) }
    }

    @Test func freezingWithoutConfigureUsesDefaults() {
        var state = ConfigurationState()
        #expect(state.freeze() == RuntimeConfiguration())
        #expect(state.isFrozen)
    }

    // MARK: - Capabilities

    @Test func capabilitiesDescribeTheBaselineBuild() throws {
        let capabilities = try Hokusai.capabilities()

        #expect(capabilities.libvipsVersion == String(cString: vips_version_string()))
        for format in [ImageFormat.jpeg, .png, .webp] {
            #expect(capabilities.canDecode(format))
            #expect(capabilities.canEncode(format))
        }
        // Cairo PDF output is part of the baseline contract.
        #expect(capabilities.canEncode(.pdf))
        #expect(capabilities.textRendering)
        // Only formats with a typed Hokusai encoder are reported as outputs.
        #expect(capabilities.outputFormats.isSubset(of: [.jpeg, .png, .webp, .avif, .heif, .tiff, .gif, .pdf]))
    }

    @Test(.enabled(if: (try? Hokusai.capabilities().canEncode(.avif)) ?? false, "AVIF not available in this libvips build"))
    func advertisedAVIFOutputActuallyEncodes() async throws {
        let output = try await Hokusai(data: loadFixtureData(named: "pixel", ext: "png")).avif().data()
        #expect(output.info.format == .avif)
    }

    @Test func capabilitiesAreSafeToQueryConcurrently() async throws {
        let expected = try Hokusai.capabilities()
        try await withThrowingTaskGroup(of: RuntimeCapabilities.self) { group in
            for _ in 0..<32 { group.addTask { try Hokusai.capabilities() } }
            for try await capabilities in group { #expect(capabilities == expected) }
        }
    }

    // MARK: - Status

    @Test func statusReportsEffectiveSchedulerSettings() async throws {
        let status = Hokusai.runtimeStatus
        #expect(status.maxConcurrentEvaluations == EvaluationScheduler.shared.limit)
        #expect(status.vipsConcurrency != nil)
        #expect(status.queuedEvaluations >= 0)
        #expect(status.activeEvaluations >= 0)

        await withTaskGroup(of: RuntimeStatus.self) { group in
            for _ in 0..<32 { group.addTask { Hokusai.runtimeStatus } }
            for await snapshot in group {
                #expect(snapshot.configuration == status.configuration)
                #expect(snapshot.activeEvaluations <= snapshot.maxConcurrentEvaluations)
            }
        }
    }
}

/// Queue bound and counters on a private scheduler (#28 / #41).
@Suite struct EvaluationQueueBoundTests {
    final class Gate: @unchecked Sendable {
        private let semaphore = DispatchSemaphore(value: 0)
        func wait() { semaphore.wait() }
        func open() { semaphore.signal() }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        Issue.record("condition not reached")
    }

    @Test func fullQueueRejectsWithResourceFailureAndKeepsCountersExact() async throws {
        let scheduler = EvaluationScheduler(limit: 1, maxQueued: 2)
        let gate = Gate()

        let holder = Task { try await scheduler.run { _ in gate.wait() } }
        try await waitUntil { scheduler.active == 1 }
        let first = Task { try await scheduler.run { _ in 1 } }
        let second = Task { try await scheduler.run { _ in 2 } }
        try await waitUntil { scheduler.queued == 2 }

        do {
            _ = try await scheduler.run { _ in 3 }
            Issue.record("expected the full queue to reject")
        } catch HokusaiError.resource(let failure) {
            #expect(failure.kind == .queuedEvaluations)
            #expect(failure.limit == 2)
            #expect(failure.actual == 2)
        }
        #expect(scheduler.queued == 2)

        gate.open()
        try await holder.value
        #expect(try await first.value == 1)
        #expect(try await second.value == 2)
        #expect(scheduler.active == 0)
        #expect(scheduler.queued == 0)
    }

    @Test func zeroQueueBoundRejectsWheneverAllSlotsAreBusy() async throws {
        let scheduler = EvaluationScheduler(limit: 1, maxQueued: 0)
        let gate = Gate()
        let holder = Task { try await scheduler.run { _ in gate.wait() } }
        try await waitUntil { scheduler.active == 1 }

        await #expect(throws: HokusaiError.self) { try await scheduler.run { _ in 0 } }

        gate.open()
        try await holder.value
        #expect(try await scheduler.run { _ in 7 } == 7)
    }
}
