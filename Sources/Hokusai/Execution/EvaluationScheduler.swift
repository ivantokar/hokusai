import Foundation
import CVips

/// Admits terminal evaluations and runs them off Swift's cooperative executor.
///
/// Two layers, deliberately separate:
/// - an asynchronous FIFO admission gate: waiting callers stay suspended Swift
///   tasks, never blocked threads, and a cancelled waiter leaves the queue
///   without starting native work;
/// - a Dispatch queue that runs only admitted, blocking libvips work.
///
/// One terminal evaluation holds exactly one slot. Composite layers and other
/// subplans are lowered inside that evaluation and never acquire a slot, so a
/// saturated scheduler cannot deadlock on its own sub-work.
///
/// `limit` bounds concurrent Hokusai evaluations; it is independent of
/// libvips' own worker-thread concurrency.
final class EvaluationScheduler: @unchecked Sendable {
    /// Process-wide scheduler used by `data()` and `write(to:)`.
    ///
    /// Creating it freezes the runtime configuration. The automatic limit is
    /// provisional until #50 chooses it from benchmarks.
    static let shared: EvaluationScheduler = {
        let configuration = VipsRuntime.frozenConfiguration()
        return EvaluationScheduler(
            limit: configuration.maxConcurrentEvaluations.fixedValue ?? automaticLimit,
            maxQueued: configuration.maxQueuedEvaluations
        )
    }()

    static var automaticLimit: Int { max(1, ProcessInfo.processInfo.activeProcessorCount) }

    let limit: Int
    let maxQueued: Int?

    // Every field below is guarded by `lock`, which makes `@unchecked Sendable`
    // sound. Continuations are resumed only after the lock is released.
    private let lock = NSLock()
    private var activeCount = 0
    private var waiters: [Waiter] = []

    private let queue = DispatchQueue(label: "com.ivantokar.hokusai.evaluation", attributes: .concurrent)

    init(limit: Int, maxQueued: Int? = nil) {
        precondition(limit > 0, "evaluation limit must be positive")
        self.limit = limit
        self.maxQueued = maxQueued
    }

    /// Evaluations currently holding a slot.
    var active: Int { lock.withLock { activeCount } }

    /// Evaluations waiting for a slot.
    var queued: Int { lock.withLock { waiters.count } }

    /// Waits for a slot, runs `work` on the blocking queue, then releases it.
    ///
    /// Task cancellation is forwarded to `work`'s ``EvaluationContext``. A
    /// failure observed after cancellation is reported as `CancellationError`;
    /// if `work` completes first, its result wins.
    func run<T: Sendable>(_ work: @escaping @Sendable (EvaluationContext) throws -> T) async throws -> T {
        try await acquire()
        defer { release() }

        let context = EvaluationContext()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    do {
                        try context.checkCancellation()
                        continuation.resume(returning: try work(context))
                    } catch {
                        continuation.resume(throwing: context.isCancelled ? CancellationError() : error)
                    }
                }
            }
        } onCancel: {
            context.cancel()
        }
    }

    // MARK: - Admission

    private final class Waiter: @unchecked Sendable {
        enum State {
            case initial
            case waiting(CheckedContinuation<Void, Error>)
            case admitted
            case cancelled
        }

        /// Guarded by the owning scheduler's lock.
        var state = State.initial
    }

    private func acquire() async throws {
        let waiter = Waiter()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                enum Admission { case admitted, cancelled, rejected(queued: Int), queued }
                let admission: Admission = lock.withLock {
                    if case .cancelled = waiter.state { return .cancelled }
                    if activeCount < limit && waiters.isEmpty {
                        activeCount += 1
                        waiter.state = .admitted
                        return .admitted
                    }
                    if let maxQueued, waiters.count >= maxQueued {
                        waiter.state = .cancelled
                        return .rejected(queued: waiters.count)
                    }
                    waiter.state = .waiting(continuation)
                    waiters.append(waiter)
                    return .queued
                }
                switch admission {
                case .admitted: continuation.resume()
                case .cancelled: continuation.resume(throwing: CancellationError())
                case .rejected(let queued):
                    continuation.resume(throwing: HokusaiError.resource(ResourceFailure(
                        kind: .queuedEvaluations,
                        limit: maxQueued,
                        actual: queued,
                        reason: "the evaluation queue is full")))
                case .queued: break
                }
            }
        } onCancel: {
            let continuation: CheckedContinuation<Void, Error>? = lock.withLock {
                switch waiter.state {
                case .initial:
                    waiter.state = .cancelled
                    return nil
                case .waiting(let continuation):
                    waiter.state = .cancelled
                    waiters.removeAll { $0 === waiter }
                    return continuation
                case .admitted, .cancelled:
                    return nil
                }
            }
            continuation?.resume(throwing: CancellationError())
        }
    }

    private func release() {
        let next: CheckedContinuation<Void, Error>? = lock.withLock {
            guard !waiters.isEmpty else {
                activeCount -= 1
                return nil
            }
            // Hand the slot straight to the oldest waiter; activeCount is unchanged.
            let waiter = waiters.removeFirst()
            guard case .waiting(let continuation) = waiter.state else {
                preconditionFailure("queued waiter must be waiting")
            }
            waiter.state = .admitted
            return continuation
        }
        next?.resume()
    }
}

/// Per-evaluation execution state shared between the evaluating thread and
/// the caller task's cancellation handler.
///
/// The registered image is held strongly, so a concurrent `cancel()` never
/// touches a released `VipsImage`. This is execution state, never part of an
/// immutable `Hokusai` value.
final class EvaluationContext: @unchecked Sendable {
    // Guarded by `lock`.
    private let lock = NSLock()
    private var cancelled = false
    private var registeredSink: NativeImage?
    private var watchedSources: [WatchedSource] = []

    private struct WatchedSource {
        let label: String
        let sequential: Bool
        let probe: NativeImage
    }

    var isCancelled: Bool { lock.withLock { cancelled } }

    func checkCancellation() throws {
        if isCancelled { throw CancellationError() }
    }

    /// Requests cancellation and kills the registered native evaluation, if any.
    func cancel() {
        lock.withLock {
            cancelled = true
            if let registeredSink { swift_vips_image_kill(registeredSink.pointer) }
        }
    }

    /// Wraps a freshly opened source so a later failure to produce its pixels
    /// can be recognised as a decode failure. Returns the image to build on.
    func watch(_ source: NativeImage, label: String, sequential: Bool) throws -> NativeImage {
        let probe = try source.probingSource()
        lock.withLock { watchedSources.append(WatchedSource(label: label, sequential: sequential, probe: probe)) }
        return probe
    }

    /// The first watched source that failed to produce pixels, if any.
    func sourceFailure() -> (label: String, reason: String)? {
        let failed = lock.withLock { watchedSources.first { $0.probe.sourceProbeFailed } }
        return failed.map {
            ($0.label, $0.sequential
                ? "the source could not be read; with sequential access this also happens when an operation reads pixels out of order"
                : "the image data could not be decoded")
        }
    }

    /// Wraps `image` in a private pass-through image and registers it as the
    /// image whose evaluation `cancel()` stops.
    ///
    /// The wrapper is outside libvips' operation cache, so killing it cannot
    /// affect concurrent evaluations that share cached upstream images.
    func sink(for image: NativeImage) throws -> NativeImage {
        let wrapper = try NativeImage.producing({ output in
            guard let wrapped = swift_vips_evaluation_image(image.pointer) else { return -1 }
            output.pointee = wrapped
            return 0
        }, failure: { .runtime(.native("prepare evaluation", "could not create the evaluation sink")) })
        try lock.withLock {
            if cancelled { throw CancellationError() }
            registeredSink = wrapper
        }
        return wrapper
    }
}
