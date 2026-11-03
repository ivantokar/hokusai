import Foundation
import Hokusai
import Testing

/// Writing a pipeline to a file it reads (#111). The destination is opened,
/// and truncated, at the first encoded byte while a decode may still be
/// reading it, and a failed write removes the destination, so the source would
/// be lost. Hokusai refuses instead, as Sharp does, and leaves the file alone.
@Suite struct SameFileWriteTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hokusai-samefile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A PNG large enough that a sequential decode is still reading when the first output byte is written.
    private func source(in folder: URL, name: String = "photo.png") async throws -> (url: URL, bytes: Data) {
        let bytes = try await Hokusai(data: tiffData(gradient(width: 1600, height: 1600))).png(compressionLevel: 0).data().data
        let url = folder.appendingPathComponent(name)
        try bytes.write(to: url)
        return (url, bytes)
    }

    private func expectRefused(_ operation: () async throws -> Void, sourceIntactAt url: URL, bytes: Data) async throws {
        do {
            try await operation()
            Issue.record("expected the write to be refused")
        } catch let error as HokusaiError {
            guard case .invalidOption(let name, _) = error else { Issue.record("expected invalidOption, got \(error)"); return }
            #expect(name == "output URL")
        }
        #expect(try Data(contentsOf: url) == bytes, "the source must be untouched")
    }

    @Test(arguments: [InputOptions.AccessMode.random, .sequential])
    func theSameFileIsRefusedAndKept(access: InputOptions.AccessMode) async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (url, bytes) = try await source(in: folder)
        try await expectRefused({
            _ = try await Hokusai(url: url, options: InputOptions(access: access)).png(compressionLevel: 9).write(to: url)
        }, sourceIntactAt: url, bytes: bytes)
    }

    @Test func aSymbolicLinkToTheSourceIsTheSameFile() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (url, bytes) = try await source(in: folder)
        let link = folder.appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        try await expectRefused({ _ = try await Hokusai(url: url).png().write(to: link) }, sourceIntactAt: url, bytes: bytes)
    }

    @Test func aHardLinkToTheSourceIsTheSameFile() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (url, bytes) = try await source(in: folder)
        let hard = folder.appendingPathComponent("hard.png")
        try FileManager.default.linkItem(at: url, to: hard)
        try await expectRefused({ _ = try await Hokusai(url: hard).png().write(to: url) }, sourceIntactAt: url, bytes: bytes)
    }

    @Test func aDifferentPathToTheSameFileIsTheSameFile() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (url, bytes) = try await source(in: folder)
        let roundabout = folder.appendingPathComponent("sub/../photo.png")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try await expectRefused({ _ = try await Hokusai(url: url).png().write(to: roundabout) }, sourceIntactAt: url, bytes: bytes)
    }

    @Test func anOverlayFileIsASourceToo() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (overlay, bytes) = try await source(in: folder, name: "overlay.png")
        let base = try Hokusai(data: tiffData(gradient(width: 64, height: 64)))
        let composed = try base.composite([CompositeLayer(Hokusai(url: overlay), placement: .gravity(.center))])
        try await expectRefused({ _ = try await composed.png().write(to: overlay) }, sourceIntactAt: overlay, bytes: bytes)
    }

    @Test func pdfOutputIsCheckedToo() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (url, bytes) = try await source(in: folder)
        try await expectRefused({ _ = try await Hokusai(url: url).pdf().write(to: url) }, sourceIntactAt: url, bytes: bytes)
    }

    @Test func aDifferentOrNewFileStillWorks() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (url, bytes) = try await source(in: folder)
        let fresh = folder.appendingPathComponent("small.png")
        let info = try await Hokusai(url: url).resize(width: 100).png().write(to: fresh)
        #expect(info.width == 100)
        let existing = folder.appendingPathComponent("existing.png")
        try Data("old".utf8).write(to: existing)
        _ = try await Hokusai(url: url).resize(width: 50).png().write(to: existing)
        #expect(try await Hokusai(url: existing).metadata().width == 50)
        #expect(try Data(contentsOf: url) == bytes)
    }
}
