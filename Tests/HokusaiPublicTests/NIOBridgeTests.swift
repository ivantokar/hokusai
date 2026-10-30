import Foundation
import Hokusai
import HokusaiNIO
import NIOCore
import Testing

/// `HokusaiNIO` moves bytes between `ByteBuffer` and Hokusai without ever
/// sharing mutable storage: whatever the transfer strategy, the pipeline means
/// what the readable bytes meant when it was created.
@Suite struct NIOBridgeTests {
    private let source = gradient(width: 24, height: 16)
    private let large = gradient(width: 320, height: 240)
    private let strategies: [ByteBuffer.ByteTransferStrategy] = [.automatic, .copy, .noCopy]

    private func buffer(_ data: Data, padding: Int = 0) -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: data.count + padding)
        buffer.writeBytes([UInt8](repeating: 0xEE, count: padding))
        buffer.writeBytes(data)
        buffer.moveReaderIndex(forwardBy: padding)
        return buffer
    }

    @Test func onlyReadableBytesAreUsedAndIndicesAreUntouched() async throws {
        // 37 unreadable bytes precede the image; they must not reach the decoder.
        let input = buffer(tiffData(source), padding: 37)
        let (reader, writer) = (input.readerIndex, input.writerIndex)

        let image = try Hokusai(buffer: input)
        #expect(input.readerIndex == reader && input.writerIndex == writer)
        expectPixels(try await rasterize(image), match: source)
    }

    @Test func everyStrategyMeansTheSameImage() async throws {
        let bytes = tiffData(source)
        for strategy in strategies {
            let image = try Hokusai(buffer: buffer(bytes, padding: 5), byteTransferStrategy: strategy)
            expectPixels(try await rasterize(image), match: source)
        }
    }

    @Test func theSourceSurvivesReleaseReuseAndMutationOfTheBuffer() async throws {
        let bytes = tiffData(source)
        for strategy in strategies {
            var input = buffer(bytes)
            let image = try Hokusai(buffer: input, byteTransferStrategy: strategy)
            // Overwrite the caller's storage, then drop it.
            input.setBytes([UInt8](repeating: 0, count: bytes.count), at: input.readerIndex)
            input.clear()
            input.writeBytes([UInt8](repeating: 0x55, count: bytes.count))
            input = ByteBuffer()
            expectPixels(try await rasterize(image), match: source)
        }
    }

    @Test func aSmallSliceOfALargeBufferIsAFullImage() async throws {
        let bytes = tiffData(source)
        var large = ByteBufferAllocator().buffer(capacity: 4 << 20)
        large.writeBytes([UInt8](repeating: 0xEE, count: 2 << 20))
        large.writeBytes(bytes)
        large.writeBytes([UInt8](repeating: 0xEE, count: 2 << 20))
        let slice = try #require(large.getSlice(at: 2 << 20, length: bytes.count))

        for strategy in strategies {
            let image = try Hokusai(buffer: slice, byteTransferStrategy: strategy)
            large = ByteBuffer()
            expectPixels(try await rasterize(image), match: source)
        }
    }

    @Test func anEmptyBufferIsInvalidInput() async throws {
        for strategy in strategies {
            do {
                _ = try await Hokusai(buffer: ByteBuffer(), byteTransferStrategy: strategy).png().data()
                Issue.record("expected an error for an empty buffer")
            } catch HokusaiError.invalidInput {
            } catch {
                Issue.record("expected invalidInput, got \(error)")
            }
        }
    }

    @Test func theByteBufferTerminalMatchesDataForEveryEncoder() async throws {
        let pipelines: [Hokusai] = try [
            source.pipeline().png(),
            source.pipeline().tiff(compression: .none),
            source.pipeline().jpeg(quality: 80),
            source.pipeline().webp(lossless: true),
        ]
        for pipeline in pipelines {
            let data = try await pipeline.data()
            let nio = try await pipeline.byteBuffer()
            #expect(nio.info == data.info)
            #expect(nio.info.byteCount == nio.buffer.readableBytes)
            #expect(nio.buffer.readableBytesView.elementsEqual(data.data))
        }
    }

    @Test func theByteBufferTerminalUsesTheGivenAllocator() async throws {
        let allocator = ByteBufferAllocator()
        let output = try await source.pipeline().png().byteBuffer(allocator: allocator)
        let decoded = try await rasterize(encoded: Data(output.buffer.readableBytesView))
        expectPixels(decoded, match: source)
    }

    @Test func theByteBufferTerminalReportsTheSameErrorsAsData() async throws {
        let pipeline = try source.pipeline(options: InputOptions(limits: InputLimits(maxPixels: 10))).png()
        do {
            _ = try await pipeline.byteBuffer()
            Issue.record("expected a resource error")
        } catch HokusaiError.resource(let resource) {
            #expect(resource.limit == 10)
        } catch {
            Issue.record("expected resource, got \(error)")
        }
    }

    // MARK: - Streaming

    private struct ConsumerFailure: Error {}

    @Test func streamedBuffersJoinToTheBytesOfData() async throws {
        let pipeline = try large.pipeline().png(compressionLevel: 0)
        let direct = try await pipeline.data()
        var buffers: [ByteBuffer] = []
        let info = try await pipeline.writeByteBuffers(chunkSize: 3000) { buffers.append($0) }

        #expect(buffers.count > 2)
        #expect(buffers.allSatisfy { $0.readableBytes > 0 && $0.readableBytes <= 3000 })
        #expect(buffers.dropLast().allSatisfy { $0.readableBytes == 3000 })
        let joined = buffers.flatMap { Array($0.readableBytesView) }
        #expect(joined == [UInt8](direct.data))
        #expect(info == direct.info)
        #expect(info.byteCount == joined.count)
    }

    @Test func streamedBuffersAreIndependentOfEachOther() async throws {
        let pipeline = try large.pipeline().png(compressionLevel: 0)
        var held: [ByteBuffer] = []
        try await pipeline.writeByteBuffers(chunkSize: 2000) { buffer in
            var copy = buffer
            held.append(copy)
            copy.clear()          // a consumer reusing its buffer must not affect the stream
        }
        let direct = try await pipeline.data()
        #expect(held.flatMap { Array($0.readableBytesView) } == [UInt8](direct.data))
    }

    @Test func aConsumerErrorStopsTheStreamAndIsRethrown() async throws {
        let pipeline = try large.pipeline().png(compressionLevel: 0)
        var seen = 0
        do {
            try await pipeline.writeByteBuffers(chunkSize: 2000) { _ in
                seen += 1
                if seen == 2 { throw ConsumerFailure() }
            }
            Issue.record("expected the consumer's error")
        } catch is ConsumerFailure {
            #expect(seen == 2)
        } catch {
            Issue.record("expected ConsumerFailure, got \(error)")
        }
    }

    @Test func cancellingTheCallerStopsAStalledStream() async throws {
        let pipeline = try gradient(width: 1000, height: 1000).pipeline().png(compressionLevel: 0)
        let task = Task {
            try await pipeline.writeByteBuffers(chunkSize: 4096) { _ in try await Task.sleep(for: .seconds(60)) }
        }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch {
            #expect(error is CancellationError)
        }
    }

    @Test func aPDFStreamsThroughTheSameContract() async throws {
        guard (try? Hokusai.capabilities().canEncode(.pdf)) == true else { return }
        var bytes: [UInt8] = []
        let info = try await source.pipeline().pdf().writeByteBuffers(chunkSize: 2048) { bytes += $0.readableBytesView }
        #expect(bytes.starts(with: Array("%PDF-".utf8)))
        #expect(info.format == .pdf && info.byteCount == bytes.count)
    }

    @Test func anEncoderIsRequiredToStream() async throws {
        do {
            try await source.pipeline().writeByteBuffers { _ in }
            Issue.record("expected invalidOption")
        } catch HokusaiError.invalidOption {
        } catch {
            Issue.record("expected invalidOption, got \(error)")
        }
    }
}
