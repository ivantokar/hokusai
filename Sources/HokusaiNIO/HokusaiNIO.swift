import Foundation
import Hokusai
import NIOCore
import NIOFoundationCompat

/// SwiftNIO bridges for Hokusai.
///
/// This optional product moves readable bytes into the pipeline so a caller's
/// `ByteBuffer` may be released, reused or mutated before asynchronous
/// evaluation.
public extension Hokusai {
    /// Adopts the readable bytes of a NIO buffer as an immutable Hokusai input.
    ///
    /// Only `readerIndex..<writerIndex` is read and the buffer's indices are
    /// not changed. The pipeline stays valid after `buffer` is released,
    /// reused, sliced or mutated: a no-copy transfer retains the storage, and
    /// `ByteBuffer` copies it before any later write.
    ///
    /// - Parameter byteTransferStrategy: How the bytes reach Hokusai.
    ///   `.automatic` lets NIO choose, so a small slice of a large allocation
    ///   is copied rather than pinning the allocation. Use `.copy` to never
    ///   retain the buffer's storage and `.noCopy` to never copy.
    init(
        buffer: ByteBuffer,
        options: InputOptions = .init(),
        byteTransferStrategy: ByteBuffer.ByteTransferStrategy = .automatic
    ) throws {
        self = try Hokusai(data: Data(buffer: buffer, byteTransferStrategy: byteTransferStrategy), options: options)
    }
}

/// Encoded bytes in a NIO buffer with the facts about how they were produced.
public struct NIOOutput: Sendable {
    /// The encoded image.
    public let buffer: ByteBuffer
    /// The encoded format, dimensions and actual byte count.
    public let info: OutputInfo
}

public extension Hokusai {
    /// Evaluates and encodes the pipeline into a buffer from `allocator`.
    ///
    /// Encoder options and metadata policy are exactly those of ``data()`` and
    /// ``write(to:)``. The complete result is held in memory, so this is a
    /// convenience for callers that need a `ByteBuffer`, not a streaming path.
    /// The encoded bytes are copied once, straight into the allocator's buffer.
    func byteBuffer(allocator: ByteBufferAllocator = ByteBufferAllocator()) async throws -> NIOOutput {
        let output = try await data()
        return NIOOutput(buffer: ByteBuffer(output.data, allocator: allocator), info: output.info)
    }
}

public extension Output {
    /// Returns owned output bytes in a fresh NIO buffer.
    var byteBuffer: ByteBuffer {
        ByteBuffer(data: data)
    }
}

private extension ByteBuffer {
    init(_ data: Data, allocator: ByteBufferAllocator) {
        self = allocator.buffer(capacity: data.count)
        writeBytes(data)
    }
}
