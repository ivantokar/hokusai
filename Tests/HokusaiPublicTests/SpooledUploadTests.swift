import Foundation
import Hokusai
import HokusaiNIO
import NIOCore
import Testing

/// Large uploads without holding them in memory (#112): an upload that arrives in chunks is kept in
/// memory while it is small, spooled to a temporary file when it is not, bounded while it is read,
/// and the file is gone when nothing can read it any more.
@Suite struct SpooledUploadTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("spool-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func files(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    /// The upload cut into chunks, counting how many were requested.
    private final class Chunks: AsyncSequence, @unchecked Sendable {
        typealias Element = Data
        let data: Data
        let size: Int
        let failAfter: Int?
        let pause: Bool
        private let lock = NSLock()
        private var _requested = 0
        var requested: Int { lock.withLock { _requested } }

        init(_ data: Data, size: Int, failAfter: Int? = nil, pause: Bool = false) {
            self.data = data; self.size = size; self.failAfter = failAfter; self.pause = pause
        }

        struct Boom: Error {}

        struct Iterator: AsyncIteratorProtocol {
            let owner: Chunks
            var offset = 0
            var index = 0
            mutating func next() async throws -> Data? {
                owner.lock.withLock { owner._requested += 1 }
                if let limit = owner.failAfter, index >= limit { throw Boom() }
                if owner.pause { try await Task.sleep(nanoseconds: 5_000_000_000) }
                guard offset < owner.data.count else { return nil }
                let end = Swift.min(offset + owner.size, owner.data.count)
                defer { offset = end; index += 1 }
                return owner.data.subdata(in: offset..<end)
            }
        }

        func makeAsyncIterator() -> Iterator { Iterator(owner: self) }
    }

    private func jpeg() throws -> Data { try fixtureData(named: "landscape-asym", ext: "jpg") }

    // MARK: Memory or file

    @Test func aSmallUploadStaysInMemory() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try jpeg()
        let pipeline = try await Hokusai(
            spooling: Chunks(image, size: 4096), memoryLimit: image.count, spoolDirectory: directory)
        #expect(files(in: directory).isEmpty, "an upload within the memory limit never touches the disk")
        let info = try await pipeline.resize(width: 64).png().data().info
        #expect(info.width == 64)
    }

    @Test func aLargeUploadIsSpooledAndDecodesLikeTheSameBytesInMemory() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try jpeg()
        let pipeline = try await Hokusai(
            spooling: Chunks(image, size: 1000), memoryLimit: 1024, spoolDirectory: directory)
        #expect(files(in: directory).count == 1)
        let spooled = try await pipeline.resize(width: 80).png().data().data
        let direct = try await Hokusai(data: image).resize(width: 80).png().data().data
        #expect(spooled == direct)
        let metadata = try await pipeline.metadata()
        #expect(metadata.sourceByteSize == image.count)
    }

    @Test func theSpoolFileIsPrivateAndNamedAsDocumented() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pipeline = try await Hokusai(spooling: Chunks(try jpeg(), size: 2048), memoryLimit: 0, spoolDirectory: directory)
        let name = try #require(files(in: directory).first)
        #expect(name.hasPrefix("hokusai-upload-"))
        let mode = (try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(name).path)[.posixPermissions] as? NSNumber)?.intValue
        #expect(mode == 0o600)
        withExtendedLifetime(pipeline) {}
    }

    @Test func chunksOfAnySizeIncludingEmptyOnesAreAccepted() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try jpeg()
        for size in [1, 7, 4096, image.count + 10] {
            let pipeline = try await Hokusai(spooling: Chunks(image, size: size), memoryLimit: 100, spoolDirectory: directory)
            #expect(try await pipeline.resize(width: 16).png().data().info.width == 16)
        }
        let withEmpties = AsyncStream<Data> { continuation in
            continuation.yield(Data()); continuation.yield(image); continuation.yield(Data()); continuation.finish()
        }
        let pipeline = try await Hokusai(spooling: withEmpties, memoryLimit: 0, spoolDirectory: directory)
        #expect(try await pipeline.resize(width: 16).png().data().info.width == 16)
    }

    // MARK: Cleanup

    @Test func theFileGoesWhenTheLastCopyOfThePipelineIsReleased() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let pipeline = try await Hokusai(spooling: Chunks(try jpeg(), size: 2048), memoryLimit: 0, spoolDirectory: directory)
            let branch = try pipeline.resize(width: 40).png()
            _ = try await branch.data()
            #expect(files(in: directory).count == 1, "still readable while a pipeline refers to it")
            _ = try await pipeline.png().data()
            withExtendedLifetime(branch) {}
        }
        #expect(files(in: directory).isEmpty)
    }

    @Test func aBranchKeepsTheFileAliveAfterTheOriginalIsGone() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let branch: Hokusai
        do {
            let pipeline = try await Hokusai(spooling: Chunks(try jpeg(), size: 2048), memoryLimit: 0, spoolDirectory: directory)
            branch = try pipeline.resize(width: 40).png()
        }
        #expect(try await branch.data().info.width == 40)
        #expect(files(in: directory).count == 1)
    }

    @Test func aFailingSequenceLeavesNothingBehind() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        await #expect(throws: Chunks.Boom.self) {
            _ = try await Hokusai(
                spooling: Chunks(try jpeg(), size: 1000, failAfter: 5), memoryLimit: 100, spoolDirectory: directory)
        }
        #expect(files(in: directory).isEmpty)
    }

    @Test func cancellingTheCallerLeavesNothingBehind() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try jpeg()
        let task = Task {
            try await Hokusai(spooling: Chunks(image, size: 1000, pause: true), memoryLimit: 0, spoolDirectory: directory)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        await #expect(throws: (any Error).self) { _ = try await task.value }
        #expect(files(in: directory).isEmpty)
    }

    // MARK: Limits while reading

    @Test func theLimitStopsTheReadAtTheChunkThatCrossesIt() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let body = Data(count: 100_000)
        let chunks = Chunks(body, size: 1000)
        let options = InputOptions(limits: InputLimits(maxBytes: 10_000))
        do {
            _ = try await Hokusai(spooling: chunks, options: options, memoryLimit: 2000, spoolDirectory: directory)
            Issue.record("expected a resource error")
        } catch HokusaiError.resource(let failure) {
            #expect(failure.kind == .encodedBytes)
        }
        #expect(chunks.requested <= 12, "stopped near the limit instead of reading all 100 chunks, requested \(chunks.requested)")
        #expect(files(in: directory).isEmpty)
    }

    @Test func anEmptyUploadIsInvalidInput() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        for body in [Data(), Data()] {
            do {
                _ = try await Hokusai(spooling: Chunks(body, size: 10), memoryLimit: 0, spoolDirectory: directory)
                Issue.record("expected invalidInput")
            } catch HokusaiError.invalidInput {
            }
        }
        #expect(files(in: directory).isEmpty)
    }

    @Test func aMissingDirectoryIsAnIOError() async throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString)")
        do {
            _ = try await Hokusai(spooling: Chunks(try jpeg(), size: 100), memoryLimit: 0, spoolDirectory: missing)
            Issue.record("expected an io error")
        } catch HokusaiError.io(_, let operation, _) {
            #expect(operation == .write)
        }
    }

    @Test func badOptionsAreRejected() async throws {
        await #expect(throws: HokusaiError.self) {
            _ = try await Hokusai(spooling: Chunks(Data(count: 4), size: 2), memoryLimit: -1)
        }
        await #expect(throws: HokusaiError.self) {
            _ = try await Hokusai(spooling: Chunks(Data(count: 4), size: 2), options: InputOptions(page: -1))
        }
    }

    // MARK: NIO

    @Test func byteBuffersSpoolTheSameWay() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try jpeg()
        let buffers = AsyncStream<ByteBuffer> { continuation in
            var offset = 0
            while offset < image.count {
                let end = min(offset + 3000, image.count)
                continuation.yield(ByteBuffer(bytes: image[offset..<end]))
                offset = end
            }
            continuation.finish()
        }
        let pipeline = try await Hokusai(spooling: buffers, memoryLimit: 1024, spoolDirectory: directory)
        #expect(files(in: directory).count == 1)
        #expect(try await pipeline.resize(width: 32).png().data().info.width == 32)
    }
}
