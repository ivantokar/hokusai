import Foundation
import Hokusai
import HokusaiNIO
import NIOCore
import Testing

/// Process lifecycle, shared-source concurrency, source ownership and the
/// NIO bridge: behaviour a caller depends on without seeing any internals.
@Suite struct LifecycleAndInteropTests {
    init() throws { try Hokusai.initialize() }

    // MARK: - Initialization

    @Test func repeatedInitializationIsIdempotent() async throws {
        try Hokusai.initialize()
        try Hokusai.initialize()
        try Hokusai.initialize()

        // The runtime must remain usable afterwards.
        let metadata = try await Hokusai(data: fixtureData(named: "pixel", ext: "png")).metadata()
        #expect(metadata.width == 1)
    }

    @Test func concurrentInitializationDoesNotRace() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<32 { group.addTask { try Hokusai.initialize() } }
            try await group.waitForAll()
        }
    }

    // MARK: - Concurrent use of one source

    @Test func concurrentLoadsFromDataAndFiles() async throws {
        let data = try fixtureData(named: "landscape-asym", ext: "jpg")
        let url = try fixtureURL(named: "landscape-asym", ext: "jpg")

        try await withThrowingTaskGroup(of: Int.self) { group in
            for index in 0..<16 {
                group.addTask {
                    let image = index.isMultiple(of: 2) ? try Hokusai(data: data) : try Hokusai(url: url)
                    return try await image.metadata().width
                }
            }
            for try await width in group { #expect(width == 320) }
        }
    }

    @Test func branchesOfOneSharedPipelineEvaluateConcurrently() async throws {
        let shared = try Hokusai(url: fixtureURL(named: "landscape-asym", ext: "jpg")).autoOrient()

        async let small = shared.resize(width: 64).jpeg().data()
        async let square = shared.resize(width: 80, height: 80, fit: .cover).png().data()
        let (smallResult, squareResult) = try await (small, square)

        #expect(smallResult.info.width == 64)
        #expect(squareResult.info.width == 80 && squareResult.info.height == 80)
    }

    @Test func manyEvaluationsOfOneSharedResizeAgree() async throws {
        let shared = try Hokusai(url: fixtureURL(named: "landscape-asym", ext: "jpg"))

        try await withThrowingTaskGroup(of: [Int].self) { group in
            for _ in 0..<24 {
                group.addTask {
                    let info = try await shared.resize(width: 64).png().data().info
                    return [info.width, info.height]
                }
            }
            for try await size in group { #expect(size == [64, 40]) }
        }
    }

    @Test func manyEncodingsOfOneSharedPipelineProduceOutput() async throws {
        let shared = try Hokusai(url: fixtureURL(named: "landscape-asym", ext: "jpg")).resize(width: 64, height: 40)

        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<16 { group.addTask { try await shared.jpeg(quality: 85).data().data.count } }
            for try await size in group { #expect(size > 0) }
        }
    }

    @Test func repeatedPipelineCreationAndEvaluationStaysStable() async throws {
        let data = try fixtureData(named: "landscape-asym", ext: "jpg")
        // Every iteration opens a source, resizes and encodes; a double free
        // or a release of a borrowed pointer would crash this loop.
        for _ in 0..<200 {
            _ = try await Hokusai(data: data).resize(width: 32).jpeg(quality: 80).data()
        }
    }

    // MARK: - Source ownership

    @Test func aBufferSourceOutlivesTheCallersData() async throws {
        var transient = try fixtureData(named: "landscape-asym", ext: "jpg")
        let image = try Hokusai(data: transient)

        // Clobber and drop the original storage before any pixel is pulled.
        transient.resetBytes(in: 0..<transient.count)
        transient = Data()

        #expect(try await image.metadata().width == 320)
        #expect(try await image.resize(width: 64).png().data().info.width == 64)
    }

    @Test func aTypicalPipelineBuildsSynchronouslyAndEncodesAsynchronously() async throws {
        let output = try await Hokusai(data: fixtureData(named: "landscape-asym", ext: "jpg"))
            .autoOrient()
            .resize(width: 80, height: 80, fit: .cover, position: .attention)
            .webp(quality: 80)
            .data()

        #expect(output.info.format == .webp)
        #expect(output.info.width == 80 && output.info.height == 80)
        #expect(output.info.byteCount == output.data.count)
    }

    // MARK: - NIO

    @Test func theNIOBridgeCopiesInputAndOutputBytes() async throws {
        let input = try fixtureData(named: "pixel", ext: "png")
        var buffer = ByteBufferAllocator().buffer(capacity: input.count)
        buffer.writeBytes(input)

        let output = try await Hokusai(buffer: buffer).png().data()
        #expect(output.byteBuffer.readableBytes == output.data.count)
        #expect(output.byteBuffer.readableBytesView.elementsEqual(output.data))
    }

    // MARK: - AVIF

    /// The ISO-BMFF major brand at bytes 8..<12 identifies the codec family.
    private func majorBrand(_ data: Data) -> String {
        String(decoding: data.dropFirst(8).prefix(4), as: UTF8.self)
    }

    /// Regression: the buffer encoder once used libvips' HEVC default, so
    /// `avif().data()` returned HEIC bytes labelled as AVIF.
    @Test func avifOutputIsAV1ForDataAndFileSinks() async throws {
        guard (try? Hokusai.capabilities().canEncode(.avif)) == true else { return }
        let pipeline = try Hokusai(data: fixtureData(named: "landscape-asym", ext: "jpg")).avif(quality: 50)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hokusai-avif-\(UUID().uuidString).img")
        defer { try? FileManager.default.removeItem(at: url) }

        let output = try await pipeline.data()
        _ = try await pipeline.write(to: url)

        #expect(majorBrand(output.data) == "avif")
        let written = try Data(contentsOf: url)
        #expect(majorBrand(written) == "avif")
    }

    @Test func avifLosslessIsLargerThanLossy() async throws {
        guard (try? Hokusai.capabilities().canEncode(.avif)) == true else { return }
        let input = try fixtureData(named: "landscape-asym", ext: "jpg")
        let lossy = try await Hokusai(data: input).avif(quality: 30).data()
        let lossless = try await Hokusai(data: input).avif(lossless: true).data()
        #expect(lossless.data.count > lossy.data.count)
    }
}
