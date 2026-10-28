import Foundation
import Hokusai
import Testing

/// The same pipeline and encoder options must mean the same thing whichever
/// sink receives the bytes.
@Suite struct OutputSinkParityTests {
    private let source = gradient(width: 24, height: 16)

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("hokusai-public-\(UUID().uuidString)-\(name)")
    }

    private func isEnabled(_ format: ImageFormat) -> Bool {
        (try? Hokusai.capabilities().canEncode(format)) ?? false
    }

    /// Lossless encoders must give the same pixels from `data()` and `write(to:)`.
    @Test(arguments: [("png", ImageFormat.png), ("tif", .tiff), ("webp", .webp)])
    func losslessOutputsAgreeAcrossSinks(ext: String, format: ImageFormat) async throws {
        guard isEnabled(format) else { return }
        let encoder: Encoder = format == .webp ? .webp(WebPOptions(lossless: true)) : .init(format)
        let url = temporaryURL("parity.\(ext)")
        defer { try? FileManager.default.removeItem(at: url) }

        let pipeline = try source.pipeline().resize(width: 12, height: 8, fit: .fill).encode(using: encoder)
        let memory = try await pipeline.data()
        let info = try await pipeline.write(to: url)
        let file = try Data(contentsOf: url)

        expectPixels(try await rasterize(encoded: file), match: try await rasterize(encoded: memory.data))
        #expect(memory.info.format == format && info.format == format)
        #expect(memory.info.width == info.width && memory.info.height == info.height)
    }

    @Test func byteCountEqualsTheBytesActuallyProduced() async throws {
        let url = temporaryURL("count.png")
        defer { try? FileManager.default.removeItem(at: url) }
        let pipeline = try source.pipeline().png()

        let memory = try await pipeline.data()
        #expect(memory.info.byteCount == memory.data.count)
        let info = try await pipeline.write(to: url)
        let size = try #require(FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        #expect(info.byteCount == size)
    }

    @Test func progressiveJPEGReachesEverySink() async throws {
        let url = temporaryURL("progressive.jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        func isProgressive(_ data: Data) -> Bool {
            let bytes = [UInt8](data)
            return zip(bytes, bytes.dropFirst()).contains { $0 == 0xFF && $1 == 0xC2 }
        }

        let progressive = try source.pipeline().jpeg(quality: 85, progressive: true)
        let baseline = try source.pipeline().jpeg(quality: 85, progressive: false)
        #expect(isProgressive(try await progressive.data().data))
        _ = try await progressive.write(to: url)
        #expect(isProgressive(try Data(contentsOf: url)))
        #expect(!isProgressive(try await baseline.data().data))
    }

    @Test func interlacedPNGReachesEverySink() async throws {
        let url = temporaryURL("interlaced.png")
        defer { try? FileManager.default.removeItem(at: url) }
        /// The interlace method byte of the IHDR chunk.
        func interlaceMethod(_ data: Data) -> UInt8 { data[data.startIndex + 28] }

        let interlaced = try source.pipeline().png(interlaced: true)
        #expect(interlaceMethod(try await interlaced.data().data) == 1)
        _ = try await interlaced.write(to: url)
        #expect(interlaceMethod(try Data(contentsOf: url)) == 1)
        #expect(interlaceMethod(try await source.pipeline().png().data().data) == 0)
    }

    @Test func anExplicitEncoderWinsOverTheFileExtension() async throws {
        let url = temporaryURL("misleading.png")
        defer { try? FileManager.default.removeItem(at: url) }
        let info = try await source.pipeline().jpeg().write(to: url)
        let head = try Data(contentsOf: url).prefix(2)

        #expect(info.format == .jpeg)
        #expect(Array(head) == [0xFF, 0xD8])
    }

    @Test func theFileExtensionChoosesTheEncoderOnlyWhenNoneWasSelected() async throws {
        let url = temporaryURL("inferred.webp")
        defer { try? FileManager.default.removeItem(at: url) }
        let info = try await source.pipeline().write(to: url)
        #expect(info.format == .webp)
        #expect(try await rasterize(encoded: Data(contentsOf: url)).width == 24)
    }

    @Test func dataWithoutAnEncoderIsAnOptionError() async throws {
        do {
            _ = try await source.pipeline().data()
            Issue.record("expected data() to require an encoder")
        } catch HokusaiError.invalidOption(let name, _) {
            #expect(!name.isEmpty)
        }
    }

    @Test func lastEncoderWins() async throws {
        let output = try await source.pipeline().png().webp().jpeg().data()
        #expect(output.info.format == .jpeg)
    }

    // MARK: - Metadata policy

    @Test(arguments: [(MetadataPolicy.default, 6), (.preserveAll, 6), (.removeAll, 1), (MetadataPolicy(orientation: .remove), 1)])
    func orientationRetentionFollowsThePolicyOnEverySink(policy: MetadataPolicy, expected: Int) async throws {
        let url = temporaryURL("orientation.jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        let pipeline = try source.pipeline(orientation: 6).jpeg().metadataPolicy(policy)

        func orientation(_ data: Data) async throws -> Int {
            try await Hokusai(data: data).metadata().orientation?.rawValue ?? 1
        }
        #expect(try await orientation(pipeline.data().data) == expected)
        _ = try await pipeline.write(to: url)
        #expect(try await orientation(Data(contentsOf: url)) == expected)
    }

    @Test func autoOrientingThenKeepingTheTagDoesNotRotateTwice() async throws {
        let output = try await source.pipeline(orientation: 6).autoOrient().png().data()
        let described = try await Hokusai(data: output.data).metadata()
        // The pixels are upright, so a viewer must not rotate them again.
        #expect((described.width, described.height) == (16, 24))
        #expect((described.orientation?.rawValue ?? 1) == 1)
    }
}

private extension Encoder {
    /// The default-configured encoder for a format.
    init(_ format: ImageFormat) {
        switch format {
        case .png: self = .png()
        case .tiff: self = .tiff()
        case .webp: self = .webp()
        default: self = .jpeg()
        }
    }
}
