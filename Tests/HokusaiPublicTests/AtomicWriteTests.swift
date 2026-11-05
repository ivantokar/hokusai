import Foundation
import Hokusai
import Testing

/// `write(to:)` replaces an existing file atomically (#134): the destination is written through a
/// temporary file in the same directory and renamed over it when the write finished, so a write
/// that fails or is cancelled leaves what was there as it was.
@Suite struct AtomicWriteTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("atomic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func picture() throws -> Hokusai {
        try Hokusai(data: fixtureData(named: "landscape-asym", ext: "jpg")).resize(width: 64)
    }

    private func names(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    private func permissions(_ url: URL) throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    @Test func anExistingFileIsReplacedWithTheFinishedOutput() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("out.png")
        try Data("old".utf8).write(to: destination)
        let pipeline = try picture().png()
        let info = try await pipeline.write(to: destination)
        let expected = try await pipeline.data().data
        #expect(try Data(contentsOf: destination) == expected)
        #expect(info.byteCount == expected.count)
        #expect(try names(in: directory) == ["out.png"], "a temporary file was left behind")
    }

    @Test func aReplacedFileKeepsItsPermissions() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("keep.png")
        try Data("old".utf8).write(to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: destination.path)
        _ = try await picture().png().write(to: destination)
        #expect(try permissions(destination) == 0o640)
    }

    @Test func aNewFileIsCreatedWithoutLeavingATemporaryFile() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("new.webp")
        _ = try await picture().webp().write(to: destination)
        #expect(try names(in: directory) == ["new.webp"])
        #expect(try Data(contentsOf: destination).count > 0)
    }

    @Test func aPDFReplacesAnExistingFileToo() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("doc.pdf")
        try Data("old".utf8).write(to: destination)
        let info = try await picture().pdf().write(to: destination)
        let contents = try Data(contentsOf: destination)
        #expect(contents.prefix(4) == Data("%PDF".utf8))
        #expect(contents.count == info.byteCount)
        #expect(try names(in: directory) == ["doc.pdf"])
    }

    @Test func aSymbolicLinkStaysALinkAndItsTargetIsReplaced() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target.png")
        let link = directory.appendingPathComponent("link.png")
        try Data("old".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        _ = try await picture().png().write(to: link)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil, "the link was replaced by a file")
        #expect(try Data(contentsOf: target).prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
        #expect(try names(in: directory) == ["link.png", "target.png"])
    }

    @Test func aDeviceIsWrittenInPlace() async throws {
        let info = try await picture().png().write(to: URL(fileURLWithPath: "/dev/null"))
        #expect(info.byteCount > 0)
    }

    @Test func aFileInADirectoryThatIsNotWritableIsStillWrittenInPlace() async throws {
        let directory = try folder()
        let destination = directory.appendingPathComponent("locked.png")
        try Data("old".utf8).write(to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        guard geteuid() != 0 else { return }   // root writes anywhere, so there is nothing to fall back from
        let pipeline = try picture().png()
        _ = try await pipeline.write(to: destination)
        let expected = try await pipeline.data().data
        #expect(try Data(contentsOf: destination) == expected)
    }

    @Test func aMissingDirectoryIsStillAWriteError() async throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString)/out.png")
        do {
            _ = try await picture().png().write(to: destination)
            Issue.record("expected an I/O error")
        } catch HokusaiError.io(_, let operation, _) {
            #expect(operation == .write)
        }
    }

    @Test func aFailureBeforeAnyOutputLeavesTheExistingFileUntouched() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("keep.png")
        try Data("original".utf8).write(to: destination)
        let broken = try Hokusai(data: Data("not an image".utf8)).png()
        await #expect(throws: HokusaiError.self) { _ = try await broken.write(to: destination) }
        #expect(try Data(contentsOf: destination) == Data("original".utf8))
        #expect(try names(in: directory) == ["keep.png"])
    }
}
