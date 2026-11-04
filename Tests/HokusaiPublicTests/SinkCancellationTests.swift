import Foundation
import Hokusai
import Testing

/// Cancelling `write(to:)` at any phase (#121): the call must report either a
/// finished file or `CancellationError`, and in the second case no partial image
/// remains: a destination that did not exist is still absent, and an existing one
/// is either untouched or, when the write had begun, removed (the documented
/// behaviour; see #134 for atomic replacement). No temporary file is left behind. The `writeChunks` cases came from #113; this
/// audits the file sinks the same way.
@Suite struct SinkCancellationTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sink-cancel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func pipeline(_ encode: (Hokusai) throws -> Hokusai) throws -> Hokusai {
        try encode(Hokusai(data: fixtureData(named: "landscape-asym", ext: "jpg"))
            .resize(width: 3000, height: 2000, fit: .fill)
            .blur(sigma: 8))
    }

    private static let formats: [(name: String, ext: String)] = [
        ("png", "png"), ("jpeg", "jpg"), ("webp", "webp"), ("tiff", "tif"), ("pdf", "pdf"), ("gif", "gif"),
    ]

    @Test(arguments: formats.map(\.name), [0, 10, 40, 120, 300])
    func cancellingAtAnyPhaseLeavesNoPartialFile(format: String, delayMilliseconds: Int) async throws {
        let ext = try #require(Self.formats.first { $0.name == format }?.ext)
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appendingPathComponent("out.\(ext)")
        let previous = Data("the previous contents".utf8)
        try previous.write(to: destination)

        let source = try pipeline { image in
            switch format {
            case "png": try image.png()
            case "jpeg": try image.jpeg()
            case "webp": try image.webp()
            case "tiff": try image.tiff()
            case "pdf": try image.pdf()
            default: try image.gif()
            }
        }
        let task = Task { try await source.write(to: destination) }
        try await Task.sleep(for: .milliseconds(delayMilliseconds))
        task.cancel()

        let outcome: Result<OutputInfo, Error> = await task.result.mapError { $0 }
        let contents = try? Data(contentsOf: destination)
        switch outcome {
        case .success(let info):
            #expect(contents != nil && contents != previous, "success must have replaced the file")
            #expect(contents?.count == info.byteCount, "the file is the finished output")
        case .failure(let error):
            #expect(error is CancellationError, "unexpected error \(error)")
            // A write that stops before its first byte never touches the destination. One that stops
            // after it has already truncated the file, and Hokusai then removes what it wrote, so an
            // existing file may be gone (documented in the README). What must never remain is a partial
            // image: the file is the old one or it is absent.
            #expect(contents == nil || contents == previous, "a cancelled write left \(contents?.count ?? 0) bytes of a partial file")
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0 != destination.lastPathComponent }
        #expect(leftovers.isEmpty, "temporary files left behind: \(leftovers)")
    }

    @Test(arguments: [0, 10, 60, 200])
    func cancellingANewFileNeverLeavesAPartialOne(delayMilliseconds: Int) async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appendingPathComponent("new.png")
        let source = try pipeline { try $0.png() }
        let task = Task { try await source.write(to: destination) }
        try await Task.sleep(for: .milliseconds(delayMilliseconds))
        task.cancel()
        let outcome: Result<OutputInfo, Error> = await task.result.mapError { $0 }
        let exists = FileManager.default.fileExists(atPath: destination.path)
        switch outcome {
        case .success(let info):
            let size = exists ? try Data(contentsOf: destination).count : -1
            #expect(size == info.byteCount)
        case .failure(let error):
            #expect(error is CancellationError)
            #expect(!exists, "a cancelled write created a file")
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0 != "new.png" }
        #expect(leftovers.isEmpty, "temporary files left behind: \(leftovers)")
    }
}
