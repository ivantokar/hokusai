import Foundation
import Hokusai
import NIOCore

/// SwiftNIO bridges for Hokusai.
///
/// This optional product copies readable bytes into the pipeline so a caller's
/// `ByteBuffer` may be released or reused before asynchronous evaluation.
public extension Hokusai {
    init(buffer: ByteBuffer, options: InputOptions = .init()) throws {
        self = try Hokusai(data: Data(buffer.readableBytesView), options: options)
    }
}

public extension Output {
    /// Returns owned output bytes in a fresh NIO buffer.
    var byteBuffer: ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)
        return buffer
    }
}
