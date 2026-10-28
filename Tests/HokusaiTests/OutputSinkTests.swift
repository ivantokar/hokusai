import Foundation
import Testing
@testable import Hokusai

/// One encoder configuration must produce the same bytes and semantics for the
/// memory and file sinks (#40). Format facts are read from the encoded bytes,
/// never inferred from `OutputInfo.format`.
@Suite struct OutputSinkTests {
    init() throws { try Hokusai.initialize() }

    // MARK: - Helpers

    private func photo() throws -> Hokusai {
        try Hokusai(data: loadFixtureData(named: "landscape-asym", ext: "jpg")).resize(width: 96)
    }

    private func temporaryURL(_ name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hokusai-sink-\(UUID().uuidString)-\(name)")
    }

    /// Encodes through both terminals and returns both byte streams.
    private func bothSinks(_ pipeline: Hokusai, fileName: String = "out.bin") async throws -> (memory: Output, file: Data, info: OutputInfo) {
        let url = temporaryURL(fileName)
        defer { try? FileManager.default.removeItem(at: url) }
        let memory = try await pipeline.data()
        let info = try await pipeline.write(to: url)
        return (memory, try Data(contentsOf: url), info)
    }

    private func contains(_ data: Data, _ text: String) -> Bool {
        data.range(of: Data(text.utf8)) != nil
    }

    private var avifAvailable: Bool {
        (try? Hokusai.capabilities().canEncode(.avif)) ?? false
    }

    /// JPEG start-of-frame marker: 0xC0 baseline, 0xC2 progressive.
    private func jpegFrameMarker(_ data: Data) -> UInt8? {
        var index = 2
        while index + 4 < data.count {
            guard data[index] == 0xFF else { return nil }
            let marker = data[index + 1]
            if (0xC0...0xCF).contains(marker), marker != 0xC4, marker != 0xC8, marker != 0xCC { return marker }
            index += 2 + (Int(data[index + 2]) << 8 | Int(data[index + 3]))
        }
        return nil
    }

    /// PNG interlace method, byte 12 of the IHDR chunk body.
    private func pngInterlace(_ data: Data) -> UInt8 { data[28] }

    /// The WebP bitstream chunk: "VP8 " lossy or "VP8L" lossless. A file that
    /// carries an ICC profile starts with a "VP8X" header chunk, so the
    /// bitstream is found by its tag rather than by position.
    private func webpChunk(_ data: Data) -> String {
        contains(data, "VP8L") ? "VP8L" : (contains(data, "VP8 ") ? "VP8 " : "?")
    }

    // MARK: - Parity

    @Test func everyRasterFormatEncodesIdenticallyToMemoryAndFile() async throws {
        var pipelines: [(String, Hokusai)] = [
            ("jpeg", try photo().jpeg(quality: 70, progressive: true)),
            ("png", try photo().png(compressionLevel: 3, interlaced: true)),
            ("webp", try photo().webp(quality: 60, effort: 2)),
            ("webp-lossless", try photo().webp(lossless: true)),
        ]
        if avifAvailable { pipelines.append(("avif", try photo().avif(quality: 40, effort: 2))) }

        for (name, pipeline) in pipelines {
            let result = try await bothSinks(pipeline)
            #expect(result.memory.data == result.file, "\(name): file bytes differ from data()")
            #expect(result.info == result.memory.info, "\(name): OutputInfo differs between sinks")
            #expect(result.info.byteCount == result.file.count, "\(name): size is not the encoded byte count")
            #expect(result.info.width == 96)
        }
    }

    // MARK: - Options reach both sinks

    @Test func jpegProgressiveReachesBothSinks() async throws {
        let progressive = try await bothSinks(photo().jpeg(progressive: true))
        let baseline = try await bothSinks(photo().jpeg(progressive: false))

        #expect(jpegFrameMarker(progressive.memory.data) == 0xC2)
        #expect(jpegFrameMarker(progressive.file) == 0xC2)
        #expect(jpegFrameMarker(baseline.memory.data) == 0xC0)
        #expect(jpegFrameMarker(baseline.file) == 0xC0)
    }

    @Test func pngInterlaceReachesBothSinks() async throws {
        let interlaced = try await bothSinks(photo().png(interlaced: true))
        let plain = try await bothSinks(photo().png(interlaced: false))

        #expect(pngInterlace(interlaced.memory.data) == 1)
        #expect(pngInterlace(interlaced.file) == 1)
        #expect(pngInterlace(plain.memory.data) == 0)
        #expect(pngInterlace(plain.file) == 0)
    }

    @Test func webpLosslessReachesBothSinks() async throws {
        let lossless = try await bothSinks(photo().webp(lossless: true))
        let lossy = try await bothSinks(photo().webp(quality: 50))

        #expect(webpChunk(lossless.memory.data) == "VP8L")
        #expect(webpChunk(lossless.file) == "VP8L")
        #expect(webpChunk(lossy.memory.data) == "VP8 ")
        #expect(webpChunk(lossy.file) == "VP8 ")
    }

    @Test func compressionLevelChangesBothSinksTheSameWay() async throws {
        let fast = try await bothSinks(photo().png(compressionLevel: 0))
        let small = try await bothSinks(photo().png(compressionLevel: 9))
        #expect(fast.memory.data.count > small.memory.data.count)
        #expect(fast.file.count > small.file.count)
    }

    // MARK: - AVIF is AV1

    @Test(.enabled(if: (try? Hokusai.capabilities().canEncode(.avif)) ?? false, "AVIF not available in this libvips build"))
    func avifIsAV1InEverySinkAndHonoursOptions() async throws {
        let lossy = try await bothSinks(photo().avif(quality: 40, effort: 2))
        let lossless = try await bothSinks(photo().avif(lossless: true))

        for bytes in [lossy.memory.data, lossy.file, lossless.memory.data, lossless.file] {
            #expect(String(decoding: bytes[8..<12], as: UTF8.self) == "avif", "major brand")
            #expect(contains(bytes, "av01"), "AV1 codec configuration")
            #expect(!contains(bytes, "hvc1"), "must not be HEVC")
        }
        #expect(lossless.memory.data.count > lossy.memory.data.count)
        #expect(lossless.file.count > lossy.file.count)
    }

    // MARK: - Encoder selection

    @Test func anExplicitEncoderWinsOverTheFileExtension() async throws {
        let png = temporaryURL("actually.jpg")
        let jpeg = temporaryURL("actually.png")
        defer { try? FileManager.default.removeItem(at: png); try? FileManager.default.removeItem(at: jpeg) }

        try await photo().png().write(to: png)
        try await photo().jpeg().write(to: jpeg)

        #expect(try Data(contentsOf: png).starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(try Data(contentsOf: jpeg).starts(with: [0xFF, 0xD8, 0xFF]))
    }

    @Test func theExtensionChoosesTheEncoderOnlyWhenNoneWasSelected() async throws {
        let url = temporaryURL("inferred.webp")
        defer { try? FileManager.default.removeItem(at: url) }

        let info = try await photo().write(to: url)
        #expect(info.format == .webp)
        #expect(contains(try Data(contentsOf: url), "WEBP"))
    }

    @Test func dataRequiresAnExplicitEncoder() async throws {
        let pipeline = try photo()
        var thrown: Error?
        do {
            _ = try await pipeline.data()
        } catch {
            thrown = error
        }
        guard case HokusaiError.invalidOption(let name, _)? = thrown else {
            Issue.record("expected invalidOption, got \(String(describing: thrown))")
            return
        }
        #expect(name == "output format")
    }

    @Test func aMissingEncoderIsTheSameTypedErrorForEverySink() throws {
        let fake = RuntimeCapabilities(libvipsVersion: "test", inputFormats: [.jpeg], outputFormats: [.jpeg, .png], textRendering: false)
        let terminal = TerminalConfig()

        for format in [Encoder.webp(), .avif(), .pdf()] {
            do {
                _ = try Evaluator.selectEncoder(format, terminal, capabilities: fake)
                Issue.record("expected \(format.imageFormat) to be unsupported")
            } catch HokusaiError.unsupported(let feature, _) {
                #expect(feature == "encoding \(format.imageFormat.rawValue)")
            }
        }
        // The same selection step runs before either sink does any work.
        _ = try Evaluator.selectEncoder(.jpeg(), terminal, capabilities: fake)
    }

    // MARK: - Metadata policy

    @Test func metadataPolicyAgreesAcrossSinks() async throws {
        let source = try Hokusai(data: loadFixtureData(named: "orientation-6", ext: "jpg"))
        let removed = try await bothSinks(source.jpeg().metadataPolicy(.removeAll))
        let preserved = try await bothSinks(source.jpeg().metadataPolicy(.preserveAll))

        #expect(!contains(removed.memory.data, "Exif") && !contains(removed.file, "Exif"))
        #expect(contains(preserved.memory.data, "Exif") && contains(preserved.file, "Exif"))
        #expect(removed.memory.data == removed.file)
        #expect(preserved.memory.data == preserved.file)
    }

    // MARK: - Destination failures

    @Test(arguments: ["png", "jpeg", "webp"])
    func anUnwritableDestinationIsAWriteIOError(format: String) async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("missing-\(UUID().uuidString)")
            .appendingPathComponent("out.\(format)")
        let pipeline = try format == "png" ? photo().png() : format == "jpeg" ? photo().jpeg() : photo().webp()

        do {
            _ = try await pipeline.write(to: url)
            Issue.record("expected the write to fail")
        } catch HokusaiError.io(let failedURL, let operation, let reason) {
            #expect(failedURL == url)
            #expect(operation == .write)
            #expect(!reason.isEmpty)
        }
    }

    @Test func aFailedPipelineLeavesNoPartialFile() async throws {
        let url = temporaryURL("never.png")
        defer { try? FileManager.default.removeItem(at: url) }
        let broken = try Hokusai(data: loadFixtureData(named: "truncated", ext: "jpg")).png()

        do {
            _ = try await broken.write(to: url)
            Issue.record("expected the truncated source to fail")
        } catch HokusaiError.decode {
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aCancelledWriteLeavesNoPartialFile() async throws {
        let url = temporaryURL("cancelled.png")
        defer { try? FileManager.default.removeItem(at: url) }
        let expensive = try Hokusai(data: loadFixtureData(named: "landscape-asym", ext: "jpg"))
            .resize(width: 12000, height: 7500, fit: .fill)
            .blur(sigma: 50)
            .png(compressionLevel: 9)

        let task = Task { try await expensive.write(to: url) }
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch is CancellationError {
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    #if os(Linux)
    @Test func aFullDiskIsAWriteIOErrorAndTheDeviceIsLeftAlone() async throws {
        // /dev/full accepts open() and fails every write with ENOSPC.
        let url = URL(fileURLWithPath: "/dev/full")
        do {
            _ = try await photo().png().write(to: url)
            Issue.record("expected ENOSPC")
        } catch HokusaiError.io(let failedURL, let operation, let reason) {
            #expect(failedURL == url)
            #expect(operation == .write)
            #expect(reason.lowercased().contains("space"))
        }
        #expect(FileManager.default.fileExists(atPath: "/dev/full"))
    }
    #endif

    // MARK: - Concurrency

    @Test func concurrentWritesAndDataCallsDoNotInterfere() async throws {
        let pipeline = try photo().png(interlaced: true)
        let expected = try await pipeline.data().data

        try await withThrowingTaskGroup(of: Bool.self) { group in
            for index in 0..<24 {
                group.addTask {
                    if index.isMultiple(of: 2) {
                        return try await pipeline.data().data == expected
                    }
                    let url = self.temporaryURL("concurrent-\(index).png")
                    defer { try? FileManager.default.removeItem(at: url) }
                    try await pipeline.write(to: url)
                    return try Data(contentsOf: url) == expected
                }
            }
            for try await identical in group {
                #expect(identical)
            }
        }
    }
}
