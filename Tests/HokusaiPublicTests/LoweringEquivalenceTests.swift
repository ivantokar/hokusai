import Foundation
import Hokusai
import Testing

/// Optimisations must not change what a pipeline means (#50 section 4).
/// Each test states the reference form and compares the optimised form to it.
@Suite struct LoweringEquivalenceTests {
    private let base = gradient(width: 32, height: 24)

    /// A translucent, non-uniform layer so order and alpha both matter.
    private func layer(_ width: Int, _ height: Int, seed: Int) -> Raster {
        Raster(width: width, height: height) { x, y in
            [UInt8((x * 40 + seed * 50) % 256), UInt8((y * 30 + seed * 90) % 256), UInt8((x + y + seed * 70) % 256), UInt8(90 + seed * 50)]
        }
    }

    private func layers() throws -> [CompositeLayer] {
        try [
            CompositeLayer(layer(12, 10, seed: 1).pipeline(), x: 2, y: 3),
            CompositeLayer(layer(16, 12, seed: 2).pipeline(), x: 10, y: 8, opacity: 0.6),
            CompositeLayer(layer(8, 8, seed: 3).pipeline(), x: -3, y: 18),
        ]
    }

    // MARK: - Multi-input composite

    /// One native composite over every layer equals blending the layers one
    /// at a time in the same order.
    @Test func oneCompositeEqualsChainedCompositesForOver() async throws {
        let all = try layers()
        let together = try await rasterize(base.pipeline().composite(all))

        var chained = try base.pipeline()
        for layer in all { chained = try chained.composite([layer]) }
        expectPixels(together, match: try await rasterize(chained), .absolute(maxChannelDelta: 2))
    }

    @Test func blendModesKeepTheirOrderInOneComposite() async throws {
        let modes: [BlendMode] = [.over, .multiply, .add]
        let stacked = try modes.enumerated().map { index, mode in
            try CompositeLayer(layer(14, 14, seed: index + 1).pipeline(), x: index * 6, y: index * 4, blend: mode)
        }
        let together = try await rasterize(base.pipeline().composite(stacked))

        var chained = try base.pipeline()
        for (index, mode) in modes.enumerated() {
            chained = try chained.composite([CompositeLayer(layer(14, 14, seed: index + 1).pipeline(), x: index * 6, y: index * 4, blend: mode)])
        }
        expectPixels(together, match: try await rasterize(chained), .absolute(maxChannelDelta: 3))
    }

    /// One overlay pipeline used by two layers is the same as two identical copies.
    @Test func aSharedOverlayEqualsIndependentCopies() async throws {
        let shared = try layer(10, 10, seed: 2).pipeline().resize(width: 6)
        let withShared = try await rasterize(base.pipeline().composite([
            CompositeLayer(shared, x: 1, y: 1), CompositeLayer(shared, x: 20, y: 12),
        ]))
        let withCopies = try await rasterize(base.pipeline().composite([
            CompositeLayer(layer(10, 10, seed: 2).pipeline().resize(width: 6), x: 1, y: 1),
            CompositeLayer(layer(10, 10, seed: 2).pipeline().resize(width: 6), x: 20, y: 12),
        ]))
        expectPixels(withShared, match: withCopies)
    }

    /// Evaluating a branch first must not change a pipeline that composites it.
    @Test func evaluatingAnOverlayBeforeUsingItChangesNothing() async throws {
        let overlay = try layer(12, 12, seed: 1).pipeline().resize(width: 8)
        let fresh = try await rasterize(base.pipeline().composite([CompositeLayer(overlay, x: 4, y: 4)]))
        _ = try await rasterize(overlay)
        let afterwards = try await rasterize(base.pipeline().composite([CompositeLayer(overlay, x: 4, y: 4)]))
        expectPixels(afterwards, match: fresh)
    }

    // MARK: - Sinks

    /// Lossless output carries the same pixels to memory and to a file, and the
    /// bytes themselves are identical.
    @Test(arguments: [ImageFormat.png, .tiff, .webp])
    func losslessSinksAgreeOnBytesAndPixels(format: ImageFormat) async throws {
        guard (try? Hokusai.capabilities().canEncode(format)) == true else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hokusai-lowering-\(UUID().uuidString).\(format.rawValue)")
        defer { try? FileManager.default.removeItem(at: url) }

        let transformed = try base.pipeline().resize(width: 20).rotate(by: 90).composite(Array(layers().prefix(1)))
        let encoder: Hokusai
        switch format {
        case .tiff: encoder = try transformed.tiff(compression: .none)
        case .webp: encoder = try transformed.webp(lossless: true)
        default: encoder = try transformed.png()
        }
        let memory = try await encoder.data()
        let info = try await encoder.write(to: url)
        let file = try Data(contentsOf: url)

        #expect(file == memory.data)
        #expect(info == memory.info)
        expectPixels(try await rasterize(encoded: file), match: try await rasterize(transformed))
    }
}
