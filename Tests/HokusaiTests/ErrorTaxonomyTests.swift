import Foundation
import Testing
@testable import Hokusai

/// Each boundary classifies its own failures (#42). Assertions check cases and
/// Hokusai-owned fields, never native diagnostic text.
@Suite struct ErrorTaxonomyTests {
    init() throws { try Hokusai.initialize() }

    private func terminalError(_ body: () async throws -> Any) async -> Error? {
        do {
            _ = try await body()
            return nil
        } catch {
            return error
        }
    }

    private func image() throws -> Hokusai {
        try Hokusai(data: loadFixtureData(named: "landscape-asym", ext: "jpg"))
    }

    @Test func invalidSourcesAreInvalidInput() {
        expectHokusaiError({ try Hokusai(data: Data()) }) { $0.isInvalidInput }
        expectHokusaiError({ try Hokusai(url: URL(string: "https://example.com/a.jpg")!) }) { $0.isInvalidInput }
    }

    @Test func invalidOptionsNameTheirField() throws {
        let base = try image()
        expectHokusaiError({ try base.webp(quality: 0) }) {
            if case .invalidOption("quality", _) = $0 { return true }
            return false
        }
        expectHokusaiError({ try base.blur(sigma: .nan) }) {
            if case .invalidOption("sigma", _) = $0 { return true }
            return false
        }
    }

    @Test func corruptInputIsDecode() async throws {
        let error = await terminalError { try await Hokusai(data: Data(repeating: 0xAB, count: 64)).png().data() }
        guard case HokusaiError.decode(let context)? = error else {
            Issue.record("expected decode, got \(String(describing: error))")
            return
        }
        #expect(context.operation == "decode input data")
    }

    @Test func formatWithoutTypedEncoderIsUnsupported() async throws {
        // SVG is an input format; it has no encoder to infer from the extension.
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hokusai-\(UUID().uuidString).svg")
        let error = await terminalError { try await self.image().write(to: url) }
        guard case HokusaiError.unsupported? = error else {
            Issue.record("expected unsupported, got \(String(describing: error))")
            return
        }
    }

    @Test func failedNativeOperationIsTransform() async throws {
        // Extracting outside the image is only detectable once pixels exist.
        let error = await terminalError { try await self.image().extract(x: 300, y: 0, width: 100, height: 100).png().data() }
        guard case HokusaiError.transform(let context)? = error else {
            Issue.record("expected transform, got \(String(describing: error))")
            return
        }
        #expect(context.operation == "extract")
    }

    @Test func failedEncoderIsEncode() async throws {
        // WebP cannot encode images wider than 16383 pixels.
        let error = await terminalError { try await self.image().resize(width: 20_000, fit: .fill).webp().data() }
        guard case HokusaiError.encode(let context)? = error else {
            Issue.record("expected encode, got \(String(describing: error))")
            return
        }
        #expect(context.operation == "encode webp")
    }

    @Test func unwritableDestinationIsWriteIO() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("missing-\(UUID().uuidString)")
            .appendingPathComponent("out.pdf")
        let error = await terminalError { try await self.image().pdf().write(to: url) }
        guard case HokusaiError.io(let failedURL, .write, _)? = error else {
            Issue.record("expected io(.write), got \(String(describing: error))")
            return
        }
        #expect(failedURL == url)
    }

    @Test func layerFailuresAreScopedToTheirLayer() async throws {
        let broken = try Hokusai(data: Data(repeating: 0x11, count: 32))
        let error = await terminalError {
            try await self.image()
                .composite([CompositeLayer(self.image().resize(width: 10)), CompositeLayer(broken)])
                .png()
                .data()
        }
        guard case HokusaiError.decode(let context)? = error else {
            Issue.record("expected decode, got \(String(describing: error))")
            return
        }
        #expect(context.operation == "composite layer 2 / decode input data")
    }

    @Test func errorDescriptionsAreHokusaiOwned() {
        let context = FailureContext(operation: "resize", reason: "libvips could not complete resize", diagnostic: "vips_resize: native text")
        let description = HokusaiError.transform(context).localizedDescription
        #expect(description.contains("resize"))
        #expect(!description.contains("native text"))
    }
}
