import Foundation
import Hokusai
import HokusaiPDF
import Testing
#if canImport(Darwin)
import Darwin
#endif

/// Cancellation, memory and file output of a vector document (#158, #159, #160).
@Suite struct VectorPDFRobustnessTests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hokusai-pdf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Many pages with a paragraph each: long enough to still be drawing when the test cancels.
    private func longDocument(pages count: Int) throws -> VectorDocument {
        let paragraph = String(repeating: "Cancelling a long vector document must stop the work. ", count: 20)
        let pages = try (0..<count).map { _ in
            try VectorPage(size: .a4()).text(.plain(paragraph), at: VectorPoint(x: 40, y: 40), width: 500)
        }
        return VectorDocument(pages: pages)
    }

    // MARK: Cancellation (#158)

    @Test func cancellingWhileThePagesAreDrawnEndsWithCancellationError() async throws {
        let document = try longDocument(pages: 3000)
        let task = Task { try await document.data() }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func aCancelledWriteLeavesTheExistingFileAndNoTemporaryFile() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("report.pdf")
        try Data("old".utf8).write(to: target)
        let document = try longDocument(pages: 3000)
        let task = Task { try await document.write(to: target) }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try Data(contentsOf: target) == Data("old".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["report.pdf"])
    }

    // MARK: File output (#159, #160)

    @Test func aWrittenFileIsTheSameDocumentAndReplacesTheOldOneWithNoLeftovers() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("report.pdf")
        try Data("old".utf8).write(to: target)
        let document = try longDocument(pages: 3)
        let info = try await document.write(to: target)
        let bytes = try Data(contentsOf: target)
        #expect(bytes.prefix(5) == Data("%PDF-".utf8))
        #expect(info.pageCount == 3 && info.byteCount == bytes.count)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["report.pdf"])
    }

    @Test func aMissingDirectoryIsAnIOErrorAndCreatesNothing() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("missing").appendingPathComponent("report.pdf")
        do {
            try await longDocument(pages: 1).write(to: target)
            Issue.record("expected an error")
        } catch let error as HokusaiError {
            guard case .io = error else { Issue.record("expected an io error, got \(error)"); return }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func aNewFileGetsTheDefaultPermissions() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("report.pdf")
        try await longDocument(pages: 1).write(to: target)
        let mode = try #require(try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? Int)
        let reference = directory.appendingPathComponent("reference.txt")
        try Data("x".utf8).write(to: reference)
        let expected = try #require(try FileManager.default.attributesOfItem(atPath: reference.path)[.posixPermissions] as? Int)
        #expect(mode == expected)
    }

    // MARK: Memory (#159)

    /// The memory a document with many large images needs is that of one page, not of all of them.
    @Test func imagesAreHeldOnePageAtATime() async throws {
        let side = 1500                                // 9 MB of RGBA per image
        let pixels = Data(count: side * side * 4)
        let source = try Hokusai(raw: pixels, width: side, height: side, format: .rgba8)
        let pages = try (0..<30).map { _ in
            try VectorPage(size: .a4()).image(source, frame: VectorRect(x: 0, y: 0, width: 400, height: 400))
        }
        let document = VectorDocument(pages: pages)
        let allAtOnce = 30 * side * side * 4           // 270 MB: what holding every raster costs

        let sampler = MemorySampler()
        sampler.start()
        _ = try await document.data()
        let growth = sampler.stop()
        #expect(growth < allAtOnce / 2, "peak growth \(growth / 1_000_000) MB, all rasters would be \(allAtOnce / 1_000_000) MB")
    }
}

/// Samples this process's resident memory on a thread and reports the largest growth over the start.
private final class MemorySampler: @unchecked Sendable {
    private let lock = NSLock()
    private var peak = 0
    private var running = true
    private var baseline = 0

    func start() {
        baseline = Self.resident()
        peak = baseline
        let thread = Thread { [self] in
            while true {
                lock.lock(); let go = running; lock.unlock()
                if !go { return }
                let now = Self.resident()
                lock.lock(); peak = max(peak, now); lock.unlock()
                usleep(2_000)
            }
        }
        thread.start()
    }

    func stop() -> Int {
        lock.lock(); running = false; let result = max(peak, Self.resident()) - baseline; lock.unlock()
        return max(result, 0)
    }

    static func resident() -> Int {
        #if canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
        #else
        guard let statm = try? String(contentsOfFile: "/proc/self/statm", encoding: .utf8),
              let pages = statm.split(separator: " ").dropFirst().first.flatMap({ Int($0) }) else { return 0 }
        return pages * Int(sysconf(Int32(_SC_PAGESIZE)))
        #endif
    }
}
