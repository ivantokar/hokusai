import Foundation
import Testing
@testable import Hokusai

/// Admission, slot accounting, and cancellation contract (#41).
@Suite struct EvaluationSchedulerTests {
    init() throws { try Hokusai.initialize() }

    /// Blocks admitted work until the test opens it, so slots stay occupied.
    final class Gate: @unchecked Sendable {
        private let semaphore = DispatchSemaphore(value: 0)
        func wait() { semaphore.wait() }
        func open(_ count: Int = 1) { for _ in 0..<count { semaphore.signal() } }
    }

    /// Thread-safe log of which admitted work items started.
    final class StartLog: @unchecked Sendable {
        private let lock = NSLock()
        private var started: [Int] = []
        func record(_ id: Int) { lock.withLock { started.append(id) } }
        var values: [Int] { lock.withLock { started } }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        Issue.record("condition not reached")
    }

    @Test func excessCallersWaitSuspendedAndRunInFIFOOrder() async throws {
        let scheduler = EvaluationScheduler(limit: 1)
        let gate = Gate()
        let log = StartLog()

        let holder = Task { try await scheduler.run { _ in log.record(0); gate.wait() } }
        try await waitUntil { scheduler.active == 1 }

        var waiters: [Task<Void, Error>] = []
        for id in 1...20 {
            waiters.append(Task { try await scheduler.run { _ in log.record(id) } })
            try await waitUntil { scheduler.queued == id }
        }

        // Only the admitted evaluation reached the blocking queue.
        #expect(log.values == [0])
        #expect(scheduler.active == 1)

        gate.open()
        try await holder.value
        for waiter in waiters { try await waiter.value }

        #expect(log.values == Array(0...20))
        #expect(scheduler.active == 0)
        #expect(scheduler.queued == 0)
    }

    @Test func queuedCancellationNeverStartsNativeWork() async throws {
        let scheduler = EvaluationScheduler(limit: 1)
        let gate = Gate()
        let log = StartLog()

        let holder = Task { try await scheduler.run { _ in gate.wait() } }
        try await waitUntil { scheduler.active == 1 }

        let queued = Task { try await scheduler.run { _ in log.record(1) } }
        try await waitUntil { scheduler.queued == 1 }
        queued.cancel()

        await #expect(throws: CancellationError.self) { try await queued.value }
        #expect(scheduler.queued == 0)

        gate.open()
        try await holder.value
        #expect(log.values.isEmpty)
        #expect(scheduler.active == 0)
    }

    @Test func slotsAreReleasedAfterSuccessFailureAndCancellation() async throws {
        struct Failure: Error {}
        let scheduler = EvaluationScheduler(limit: 2)

        _ = try await scheduler.run { _ in 1 }
        await #expect(throws: Failure.self) { try await scheduler.run { _ in throw Failure() } }

        let cancelled = Task { try await scheduler.run { context in
            while !context.isCancelled { usleep(1_000) }
            try context.checkCancellation()
        } }
        try await waitUntil { scheduler.active == 1 }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }

        #expect(scheduler.active == 0)
        #expect(scheduler.queued == 0)
    }

    @Test func compositeSubplansRunInsideOneSlot() async throws {
        // With a single slot, a layer that reacquired capacity would deadlock.
        let scheduler = EvaluationScheduler(limit: 1)
        let logo = try Hokusai(data: loadFixtureData(named: "pixel", ext: "png")).resize(width: 8, fit: .fill)
        let pipeline = try Hokusai(data: loadFixtureData(named: "landscape-asym", ext: "jpg"))
            .composite([CompositeLayer(logo), CompositeLayer(logo.blur(), x: 20, y: 20)])
            .png()
        let plan = pipeline.plan, terminal = pipeline.terminal

        let output = try await scheduler.run { context in
            try Evaluator.encode(plan, terminal, as: .png(), context: context)
        }
        #expect(output.info.width == 320)
        #expect(scheduler.active == 0)
    }

    @Test func concurrentFailuresKeepTheirOwnTypedContext() async throws {
        let image = try loadFixtureData(named: "landscape-asym", ext: "jpg")
        let missing = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("missing-\(UUID().uuidString).png")

        try await withThrowingTaskGroup(of: Bool.self) { group in
            for index in 0..<48 {
                group.addTask {
                    do {
                        switch index % 3 {
                        case 0: _ = try await Hokusai(data: Data("garbage \(index)".utf8)).png().data()
                        case 1: _ = try await Hokusai(data: image).extend(to: ImageSize(width: 4, height: 4)).png().data()
                        default: _ = try await Hokusai(url: missing).png().data()
                        }
                        return false
                    } catch let error as HokusaiError {
                        switch (index % 3, error) {
                        case (0, .decode(let context)): return context.operation == "decode input data"
                        case (1, .invalidOption(let name, _)): return name == "size"
                        case (2, .io(_, let operation, _)): return operation == .read
                        default: return false
                        }
                    }
                }
            }
            for try await matched in group {
                #expect(matched)
            }
        }
    }
}

/// Cancelling running native work. Serialized: each case evaluates a
/// deliberately expensive pipeline.
@Suite(.serialized) struct NativeCancellationTests {
    init() throws { try Hokusai.initialize() }

    /// Upscales and blurs a small fixture so encoding takes seconds.
    private func expensivePipeline() throws -> Hokusai {
        try Hokusai(data: loadFixtureData(named: "landscape-asym", ext: "jpg"))
            .resize(width: 12000, height: 7500, fit: .fill)
            .blur(sigma: 50)
            .png(compressionLevel: 9)
    }

    private func cancelWhileRunning(_ pipeline: Hokusai) async throws -> (error: Error?, latency: TimeInterval) {
        let task = Task { try await pipeline.data() }
        try await Task.sleep(nanoseconds: 200_000_000)
        let cancelledAt = Date()
        task.cancel()
        do {
            _ = try await task.value
            return (nil, Date().timeIntervalSince(cancelledAt))
        } catch {
            return (error, Date().timeIntervalSince(cancelledAt))
        }
    }

    @Test func runningEvaluationStopsAndThrowsCancellationError() async throws {
        let (error, latency) = try await cancelWhileRunning(expensivePipeline())
        #expect(error is CancellationError)
        // Uncancelled, this pipeline runs for tens of seconds on CI, so any
        // bound well below that proves the cancellation was honoured. A tight
        // bound only measured runner speed (#76).
        #expect(latency < 10)
    }

    @Test func cancelledPipelineCanBeEvaluatedAgain() async throws {
        let pipeline = try expensivePipeline()
        let (error, _) = try await cancelWhileRunning(pipeline)
        #expect(error is CancellationError)

        let output = try await pipeline.data()
        #expect(output.info.width == 12000)
    }

    @Test func cancellingOneEvaluationLeavesItsSiblingRunning() async throws {
        let pipeline = try expensivePipeline()
        let sibling = Task { try await pipeline.data() }
        let (error, _) = try await cancelWhileRunning(pipeline)
        #expect(error is CancellationError)

        let output = try await sibling.value
        #expect(output.info.width == 12000)
    }
}
