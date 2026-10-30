import Foundation

/// A bounded hand-off from one blocking native producer to one async consumer.
///
/// The producer is an encoder callback running on the evaluation scheduler's
/// blocking queue. It copies the bytes it is given into owned chunks of about
/// `chunkSize`; when `depth` chunks are waiting it blocks, which is the
/// backpressure. The consumer is a Swift task that takes one chunk at a time
/// and awaits its own sink before taking the next, so memory is bounded by
/// `depth + 2` chunks: those queued, the one being filled and the one being
/// consumed.
///
/// Nothing here grows without bound and nothing waits on a cooperative
/// executor: only the producer ever blocks, and `abort()` wakes it.
final class ChunkQueue: @unchecked Sendable {
    static let maxChunkSize = 64 << 20

    let chunkSize: Int
    let depth: Int

    // Producer-only: the chunk being filled and the total accepted.
    private var filling = Data()
    private(set) var byteCount = 0

    // Guarded by `condition`.
    private let condition = NSCondition()
    private var queued: [Data] = []
    private var waiting: CheckedContinuation<Data?, Never>?
    private var finished = false
    private var aborted = false

    init(chunkSize: Int, depth: Int = 2) {
        precondition(chunkSize > 0 && depth > 0)
        self.chunkSize = chunkSize
        self.depth = depth
    }

    /// True once the consumer failed, the caller cancelled or the producer gave up.
    var isAborted: Bool {
        condition.lock()
        defer { condition.unlock() }
        return aborted
    }

    // MARK: Producer (blocking thread)

    /// Copies `count` bytes into chunks, blocking while the consumer is behind.
    /// Returns false when the stream was aborted, which must fail the encoder.
    func write(_ bytes: UnsafeRawPointer, count: Int) -> Bool {
        var offset = 0
        while offset < count {
            if filling.isEmpty { filling.reserveCapacity(chunkSize) }
            let take = min(chunkSize - filling.count, count - offset)
            filling.append((bytes + offset).assumingMemoryBound(to: UInt8.self), count: take)
            offset += take
            byteCount += take
            if filling.count == chunkSize {
                let chunk = filling
                filling = Data()
                guard push(chunk) else { return false }
            }
        }
        return !isAborted
    }

    /// Flushes the last partial chunk and ends the stream.
    func finish() -> Bool {
        if !filling.isEmpty {
            let chunk = filling
            filling = Data()
            guard push(chunk) else { return false }
        }
        condition.lock()
        finished = true
        let consumer = waiting
        waiting = nil
        condition.unlock()
        consumer?.resume(returning: nil)
        return true
    }

    private func push(_ chunk: Data) -> Bool {
        condition.lock()
        while queued.count >= depth && !aborted { condition.wait() }
        if aborted {
            condition.unlock()
            return false
        }
        if let consumer = waiting {
            waiting = nil
            condition.unlock()
            consumer.resume(returning: chunk)
        } else {
            queued.append(chunk)
            condition.unlock()
        }
        return true
    }

    // MARK: Consumer (async)

    /// The next chunk, or nil when the stream ended or was aborted.
    func next() async -> Data? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            condition.lock()
            if !queued.isEmpty {
                let chunk = queued.removeFirst()
                condition.broadcast()
                condition.unlock()
                continuation.resume(returning: chunk)
            } else if finished || aborted {
                condition.unlock()
                continuation.resume(returning: nil)
            } else {
                waiting = continuation
                condition.unlock()
            }
        }
    }

    /// Stops the stream: discards queued chunks, wakes a blocked producer and
    /// a waiting consumer. Safe to call from any thread, any number of times.
    func abort() {
        condition.lock()
        aborted = true
        queued.removeAll()
        let consumer = waiting
        waiting = nil
        condition.broadcast()
        condition.unlock()
        consumer?.resume(returning: nil)
    }
}
