import Foundation
import Hokusai
import Testing

/// Where each failure is reported and under which case: a caller must be able
/// to tell a bad argument from an unavailable codec, a limit, a missing file
/// and a broken source without reading message text.
@Suite struct ErrorClassificationTests {
    private let source = gradient(width: 16, height: 16)

    private func failure(_ body: () async throws -> Void) async -> Error? {
        do { try await body(); return nil } catch { return error }
    }

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("hokusai-errors-\(UUID().uuidString)-\(name)")
    }

    // MARK: - Reading

    @Test func aMissingFileIsAnIOReadError() async throws {
        let url = temporaryURL("missing.png")
        let error = await failure { _ = try await Hokusai(url: url).png().data() }
        guard case HokusaiError.io(let reported, let operation, _)? = error else {
            Issue.record("expected io, got \(String(describing: error))")
            return
        }
        #expect(operation == .read)
        #expect(reported.lastPathComponent == url.lastPathComponent)
    }

    @Test func theByteLimitAppliesToAFileBeforeItIsDecoded() async throws {
        let url = temporaryURL("big.tif")
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = tiffData(source)
        try bytes.write(to: url)

        let error = await failure { _ = try await Hokusai(url: url, options: InputOptions(limits: InputLimits(maxBytes: 64))).png().data() }
        guard case HokusaiError.resource(let resource)? = error else {
            Issue.record("expected resource, got \(String(describing: error))")
            return
        }
        #expect(resource.kind == .encodedBytes)
        #expect(resource.limit == 64)
        #expect(resource.actual == bytes.count)
    }

    @Test func theChannelLimitIsReportedWithItsKind() async throws {
        let image = try source.pipeline(options: InputOptions(limits: InputLimits(maxChannels: 3)))
        let error = await failure { _ = try await image.png().data() }
        guard case HokusaiError.resource(let resource)? = error else {
            Issue.record("expected resource, got \(String(describing: error))")
            return
        }
        #expect(resource.limit == 3)
        #expect(resource.actual == 4)
    }

    @Test func limitsEqualToTheInputAreAccepted() async throws {
        let bytes = tiffData(source)
        let limits = InputLimits(maxBytes: bytes.count, maxPixels: 16 * 16, maxChannels: 4)
        let output = try await Hokusai(data: bytes, options: InputOptions(limits: limits)).png().data()
        #expect(output.info.width == 16 && output.info.height == 16)
    }

    @Test func garbageIsADecodeErrorThatNamesWhatFailed() async throws {
        let error = await failure { _ = try await Hokusai(data: Data(repeating: 0x42, count: 256)).png().data() }
        guard case HokusaiError.decode(let context)? = error else {
            Issue.record("expected decode, got \(String(describing: error))")
            return
        }
        #expect(!context.operation.isEmpty)
        #expect(!context.reason.isEmpty)
    }

    // MARK: - Writing

    @Test func svgIsNotAnOutputFormat() async throws {
        let url = temporaryURL("out.svg")
        defer { try? FileManager.default.removeItem(at: url) }
        let error = await failure { _ = try await source.pipeline().write(to: url) }
        guard case HokusaiError.unsupported(let feature, _)? = error else {
            Issue.record("expected unsupported, got \(String(describing: error))")
            return
        }
        #expect(feature.contains("svg"))
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func anUnknownExtensionIsAnOptionError() async throws {
        let url = temporaryURL("out.unknown")
        let error = await failure { _ = try await source.pipeline().write(to: url) }
        guard case HokusaiError.invalidOption? = error else {
            Issue.record("expected invalidOption, got \(String(describing: error))")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    /// An encoder this build lacks fails the same way to memory and to a file,
    /// before any output exists.
    @Test(arguments: ImageFormat.allCases)
    func aMissingEncoderIsUnsupportedOnEverySink(format: ImageFormat) async throws {
        let capabilities = try Hokusai.capabilities()
        guard format != .svg, !capabilities.canEncode(format) else { return }
        let url = temporaryURL("out.\(format.rawValue)")
        defer { try? FileManager.default.removeItem(at: url) }
        let pipeline = try source.pipeline().encode(using: Encoder(format))

        let inMemory = await failure { _ = try await pipeline.data() }
        let toFile = await failure { _ = try await pipeline.write(to: url) }
        for error in [inMemory, toFile] {
            guard case HokusaiError.unsupported? = error else {
                Issue.record("expected unsupported for \(format), got \(String(describing: error))")
                continue
            }
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aFailedFileWriteLeavesAnExistingDestinationUntouched() async throws {
        let url = temporaryURL("keep.png")
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("original".utf8)
        try original.write(to: url)

        // The transform cannot run, so the evaluation fails before any output.
        let broken = try source.pipeline().extend(to: ImageSize(width: 4, height: 4)).png()
        _ = await failure { _ = try await broken.write(to: url) }
        #expect(try Data(contentsOf: url) == original)
    }

    // MARK: - Equality of reporting across entry points

    @Test func theSameFailureIsReportedWhicheverSinkEvaluatesIt() async throws {
        let url = temporaryURL("same.png")
        defer { try? FileManager.default.removeItem(at: url) }
        let pipeline = try source.pipeline(options: InputOptions(limits: InputLimits(maxPixels: 10))).png()

        let inMemory = await failure { _ = try await pipeline.data() }
        let toFile = await failure { _ = try await pipeline.write(to: url) }
        guard case HokusaiError.resource(let first)? = inMemory, case HokusaiError.resource(let second)? = toFile else {
            Issue.record("expected resource from both sinks, got \(String(describing: inMemory)) and \(String(describing: toFile))")
            return
        }
        #expect(first == second)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func errorsDescribeThemselvesForLogs() async throws {
        let error = await failure { _ = try await Hokusai(data: Data(repeating: 0x42, count: 256)).png().data() }
        let described = try #require(error as? HokusaiError).errorDescription
        #expect(described?.isEmpty == false)
    }
}
