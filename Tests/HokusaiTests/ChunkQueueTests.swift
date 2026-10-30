import Foundation
import Testing
@testable import Hokusai

/// The bounded hand-off behind `writeChunks`: coalescing, backpressure and
/// the ways a stream can end.
@Suite struct ChunkQueueTests {
    /// Runs `body` on a plain thread, as the evaluation scheduler's blocking queue does.
    private func onThread(_ body: @escaping @Sendable () -> Void) -> Thread {
        let thread = Thread { body() }
        thread.start()
        return thread
    }

    private func bytes(_ count: Int, _ value: UInt8 = 7) -> [UInt8] { [UInt8](repeating: value, count: count) }

    private func drain(_ queue: ChunkQueue) async -> [Data] {
        var chunks: [Data] = []
        while let chunk = await queue.next() { chunks.append(chunk) }
        return chunks
    }

    @Test func smallWritesAreCoalescedIntoFullChunks() async throws {
        let queue = ChunkQueue(chunkSize: 10, depth: 8)
        _ = onThread {
            for _ in 0..<35 { _ = bytes(1).withUnsafeBytes { queue.write($0.baseAddress!, count: 1) } }
            _ = queue.finish()
        }
        let chunks = await drain(queue)
        #expect(chunks.map(\.count) == [10, 10, 10, 5])
    }

    @Test func oneLargeWriteIsSplit() async throws {
        let queue = ChunkQueue(chunkSize: 16, depth: 8)
        _ = onThread {
            _ = bytes(50).withUnsafeBytes { queue.write($0.baseAddress!, count: 50) }
            _ = queue.finish()
        }
        #expect(await drain(queue).map(\.count) == [16, 16, 16, 2])
    }

    @Test func aStreamWithNoBytesHasNoChunks() async throws {
        let queue = ChunkQueue(chunkSize: 16)
        #expect(queue.finish())
        #expect(await drain(queue).isEmpty)
    }

    @Test func anExactMultipleHasNoTrailingEmptyChunk() async throws {
        let queue = ChunkQueue(chunkSize: 10, depth: 8)
        _ = onThread {
            _ = bytes(30).withUnsafeBytes { queue.write($0.baseAddress!, count: 30) }
            _ = queue.finish()
        }
        #expect(await drain(queue).map(\.count) == [10, 10, 10])
    }

    @Test func theProducerWaitsWhenTheConsumerFallsBehind() async throws {
        let queue = ChunkQueue(chunkSize: 10, depth: 2)
        let done = Flag()
        _ = onThread {
            _ = bytes(1000).withUnsafeBytes { queue.write($0.baseAddress!, count: 1000) }
            _ = queue.finish()
            done.set()
        }
        // Nothing consumes. Two chunks queue and a third is held by the blocked push.
        try await Task.sleep(for: .milliseconds(300))
        #expect(!done.isSet)
        #expect(queue.byteCount <= (queue.depth + 1) * queue.chunkSize)
        #expect(queue.byteCount >= queue.depth * queue.chunkSize)

        // Consuming lets it finish with every byte, in order.
        let chunks = await drain(queue)
        #expect(chunks.reduce(0) { $0 + $1.count } == 1000)
        #expect(chunks.count == 100)
    }

    @Test func abortWakesABlockedProducerWhichThenFails() async throws {
        let queue = ChunkQueue(chunkSize: 10, depth: 1)
        let result = Result()
        _ = onThread {
            result.set(bytes(500).withUnsafeBytes { queue.write($0.baseAddress!, count: 500) })
        }
        try await Task.sleep(for: .milliseconds(200))
        #expect(result.value == nil, "the producer should still be blocked")
        queue.abort()
        for _ in 0..<200 where result.value == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(result.value == false)
        #expect(queue.isAborted)
    }

    @Test func abortEndsAWaitingConsumer() async throws {
        let queue = ChunkQueue(chunkSize: 10)
        let waiter = Task { await queue.next() }
        try await Task.sleep(for: .milliseconds(100))
        queue.abort()
        #expect(await waiter.value == nil)
    }

    @Test func abortDiscardsQueuedChunksAndLaterWritesFail() async throws {
        let queue = ChunkQueue(chunkSize: 4, depth: 4)
        #expect(bytes(8).withUnsafeBytes { queue.write($0.baseAddress!, count: 8) })
        queue.abort()
        #expect(await queue.next() == nil)
        #expect(!bytes(8).withUnsafeBytes { queue.write($0.baseAddress!, count: 8) })
        queue.abort()   // idempotent
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

private final class Result: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Bool?
    var value: Bool? { lock.withLock { stored } }
    func set(_ value: Bool) { lock.withLock { stored = value } }
}
