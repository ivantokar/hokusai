import Foundation
import Hokusai
import Testing

/// `writeChunks` carries the same bytes as `data()`, in bounded pieces, and
/// stops promptly when the consumer fails or the caller cancels.
@Suite struct ChunkStreamingTests {
    private struct ConsumerFailure: Error, Equatable { let chunk: Int }

    private let source = gradient(width: 320, height: 240)

    private func canEncode(_ format: ImageFormat) -> Bool {
        (try? Hokusai.capabilities().canEncode(format)) ?? false
    }

    private func collect(_ pipeline: Hokusai, chunkSize: Int = 64 * 1024) async throws -> (chunks: [Data], info: OutputInfo) {
        var chunks: [Data] = []
        let info = try await pipeline.writeChunks(chunkSize: chunkSize) { chunks.append($0) }
        return (chunks, info)
    }

    // MARK: - Bytes

    @Test func chunksJoinToExactlyTheBytesOfDataForDeterministicEncoders() async throws {
        let pipelines: [(String, Hokusai)] = try [
            ("png", source.pipeline().png()),
            ("tiff", source.pipeline().tiff(compression: .none)),
            ("tiff-deflate", source.pipeline().tiff(compression: .deflate)),
            ("webp-lossless", source.pipeline().webp(lossless: true)),
            ("jpeg", source.pipeline().jpeg(quality: 80)),
        ]
        for (name, pipeline) in pipelines {
            let direct = try await pipeline.data()
            let streamed = try await collect(pipeline, chunkSize: 4096)
            #expect(Data(streamed.chunks.joined()) == direct.data, "\(name)")
            #expect(streamed.info == direct.info, "\(name)")
        }
    }

    /// TIFF cannot be written forward-only, so it is encoded first and then
    /// streamed; the contract (chunks, count, errors) is the same.
    @Test func aTIFFStreamsAfterItIsEncoded() async throws {
        let pipeline = try source.pipeline().tiff(compression: .none)
        let direct = try await pipeline.data()
        let streamed = try await collect(pipeline, chunkSize: 10_000)
        #expect(Data(streamed.chunks.joined()) == direct.data)
        #expect(streamed.chunks.allSatisfy { !$0.isEmpty && $0.count <= 10_000 })
    }

    @Test(arguments: [ImageFormat.avif, .heif, .gif])
    func otherEncodersStreamADecodableImage(format: ImageFormat) async throws {
        guard canEncode(format) else { return }
        if format == .heif, !((try? Hokusai.capabilities().canEncode(HEIFCompression.hevc)) ?? false) { return }
        let base = try source.pipeline()
        let pipeline = switch format {
        case .avif: try base.avif(quality: 50)
        case .heif: try base.heif(quality: 50)
        default: try base.gif()
        }
        let streamed = try await collect(pipeline, chunkSize: 8192)
        let bytes = Data(streamed.chunks.joined())
        #expect(streamed.info.byteCount == bytes.count)
        let decoded = try await rasterize(encoded: bytes)
        #expect(decoded.width == 320 && decoded.height == 240)
    }

    /// AVIF options reach the chunk sink exactly as they reach memory and files.
    @Test func avifEffortAndLosslessReachTheChunkSink() async throws {
        guard canEncode(.avif) else { return }
        let base = try source.pipeline()
        var bytesByEffort: [Data] = []
        for pipeline in try [base.avif(quality: 50, effort: 0), base.avif(quality: 50, effort: 9), base.avif(lossless: true)] {
            let direct = try await pipeline.data()
            let streamed = try await collect(pipeline, chunkSize: 8192)
            let joined = Data(streamed.chunks.joined())
            #expect(joined == direct.data)
            bytesByEffort.append(joined)
        }
        #expect(bytesByEffort[0] != bytesByEffort[1], "effort must change the output")
        #expect(bytesByEffort[2] != bytesByEffort[1], "lossless must change the output")
    }

    @Test func chunksAreSizedNonEmptyAndTheTotalIsExact() async throws {
        let streamed = try await collect(source.pipeline().png(compressionLevel: 0), chunkSize: 5000)
        #expect(streamed.chunks.count > 3)
        #expect(streamed.chunks.allSatisfy { !$0.isEmpty && $0.count <= 5000 })
        #expect(streamed.chunks.dropLast().allSatisfy { $0.count == 5000 })
        #expect(streamed.chunks.reduce(0) { $0 + $1.count } == streamed.info.byteCount)
    }

    @Test func aStreamSmallerThanOneChunkArrivesAsOneChunk() async throws {
        let pipeline = try Raster.solid(width: 4, height: 4, [10, 20, 30, 255]).pipeline().png()
        let streamed = try await collect(pipeline, chunkSize: 1 << 20)
        #expect(streamed.chunks.count == 1)
        #expect(streamed.chunks[0].count == streamed.info.byteCount)
    }

    @Test func aPDFStreamIsAFinishedDocument() async throws {
        guard canEncode(.pdf) else { return }
        let pipeline = try source.pipeline().pdf()
        let direct = try await pipeline.data()
        let streamed = try await collect(pipeline, chunkSize: 2048)
        let bytes = Data(streamed.chunks.joined())
        #expect(bytes.starts(with: Data("%PDF-".utf8)))
        #expect(String(decoding: bytes.suffix(16), as: UTF8.self).contains("%%EOF"))
        #expect(streamed.info.format == .pdf && streamed.info.byteCount == bytes.count)
        // Two PDF encodes differ by a few bytes (a timestamp inside a compressed object),
        // so only the size, not the bytes, is comparable between runs.
        #expect(abs(streamed.info.byteCount - direct.info.byteCount) <= direct.info.byteCount / 100)
        #expect(streamed.info.pdf?.pageWidth == direct.info.pdf?.pageWidth)
    }

    // MARK: - Arguments and errors

    @Test func anEncoderIsRequired() async throws {
        let error = await failure { _ = try await self.source.pipeline().writeChunks { _ in } }
        guard case HokusaiError.invalidOption(let name, _)? = error else {
            Issue.record("expected invalidOption, got \(String(describing: error))")
            return
        }
        #expect(name == "output format")
    }

    @Test(arguments: [0, -1, 100_000_000])
    func aChunkSizeOutOfRangeIsAnOptionError(size: Int) async throws {
        let pipeline = try source.pipeline().png()
        let error = await failure { _ = try await pipeline.writeChunks(chunkSize: size) { _ in } }
        guard case HokusaiError.invalidOption(let name, _)? = error else {
            Issue.record("expected invalidOption, got \(String(describing: error))")
            return
        }
        #expect(name == "chunkSize")
    }

    @Test func aFailureBeforeAnyOutputNeverCallsTheConsumer() async throws {
        let pipeline = try source.pipeline(options: InputOptions(limits: InputLimits(maxPixels: 10))).png()
        var calls = 0
        let error = await failure { _ = try await pipeline.writeChunks { _ in calls += 1 } }
        guard case HokusaiError.resource? = error else {
            Issue.record("expected resource, got \(String(describing: error))")
            return
        }
        #expect(calls == 0)
    }

    // MARK: - Consumer failure and cancellation

    @Test func theConsumersOwnErrorIsThrownAndEvaluationStops() async throws {
        let pipeline = try source.pipeline().png(compressionLevel: 0)
        var seen = 0
        let error = await failure {
            _ = try await pipeline.writeChunks(chunkSize: 4096) { _ in
                seen += 1
                if seen == 3 { throw ConsumerFailure(chunk: seen) }
            }
        }
        #expect(error as? ConsumerFailure == ConsumerFailure(chunk: 3))
        #expect(seen == 3)
    }

    @Test func aSlowConsumerNeverLosesOrReordersBytes() async throws {
        let pipeline = try source.pipeline().png(compressionLevel: 0)
        let direct = try await pipeline.data()
        var received = Data()
        _ = try await pipeline.writeChunks(chunkSize: 16 * 1024) { chunk in
            try await Task.sleep(for: .milliseconds(5))
            received.append(chunk)
        }
        #expect(received == direct.data)
    }

    @Test func cancellingTheCallerWhileTheEncoderWaitsDoesNotHang() async throws {
        let pipeline = try gradient(width: 1000, height: 1000).pipeline().png(compressionLevel: 0)
        let started = Date()
        let task = Task {
            try await pipeline.writeChunks(chunkSize: 4096) { _ in
                try await Task.sleep(for: .seconds(60))   // the consumer stalls, so the encoder blocks
            }
        }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        let error = await failure { _ = try await task.value }
        #expect(error is CancellationError)
        // The consumer would stall for 60 s; a CI machine under load may be slow, a hang is not.
        #expect(Date().timeIntervalSince(started) < 40)
    }

    @Test func concurrentStreamsDoNotMixTheirBytes() async throws {
        let pipelines = try (0..<6).map { index in
            try gradient(width: 64 + index * 8, height: 48).pipeline().png()
        }
        try await withThrowingTaskGroup(of: Bool.self) { group in
            for pipeline in pipelines {
                group.addTask {
                    let direct = try await pipeline.data()
                    var received = Data()
                    try await pipeline.writeChunks(chunkSize: 700) { received.append($0) }
                    return received == direct.data
                }
            }
            for try await same in group { #expect(same) }
        }
    }

    private func failure(_ body: () async throws -> Void) async -> Error? {
        do { try await body(); return nil } catch { return error }
    }
}
