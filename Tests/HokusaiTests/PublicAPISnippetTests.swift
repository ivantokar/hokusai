import Foundation
import Testing
import Hokusai

/// Canonical snippets from the public-surface contract (#51), written against
/// `import Hokusai` only, so a rename or removal that breaks them is visible.
@Suite struct PublicAPISnippetTests {
    init() throws { try Hokusai.initialize() }

    private static let pixelPNG: Data = {
        // 1×1 opaque red PNG.
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
    }()

    @Test func canonicalPipelineReadsAsDocumented() async throws {
        let base = try Hokusai(data: Self.pixelPNG).resize(width: 64, height: 32, fit: .cover, position: .attention)
        let logo = try Hokusai(data: Self.pixelPNG).resize(width: 8, height: 8, fit: .fill)

        let output = try await base
            .autoOrient()
            .composite([CompositeLayer(logo, placement: .gravity(.northWest, offsetX: 4, offsetY: 4), blend: .over, opacity: 0.8)])
            .drawText("Hi", placement: .gravity(.southEast, offsetX: 2, offsetY: 2), style: TextStyle(fontSize: 10, color: .white))
            .webp(quality: 82)
            .data()

        #expect(output.info.format == .webp)
        #expect(output.info.width == 64 && output.info.height == 32)
        #expect(output.info.byteCount == output.data.count)
    }

    @Test func colourIsTypedAndByteConvenienceTakesUInt8() throws {
        let orange = Color.sRGB8(red: 255, green: 64, blue: 0)
        #expect(orange.opacity == 1)
        #expect(orange == Color(red: 1, green: 64.0 / 255, blue: 0))
    }

    @Test func encoderSelectionIsConfigurationAndComparable() throws {
        #expect(PNGOptions(interlaced: true) != PNGOptions())
        #expect(OutputFormat.jpeg(JPEGOptions(quality: 70)) == .jpeg(JPEGOptions(quality: 70)))
    }

    @Test func runtimeAndCapabilitiesAreTheProcessLevelSurface() throws {
        let capabilities = try Hokusai.capabilities()
        #expect(!capabilities.libvipsVersion.isEmpty)
        #expect(capabilities.canEncode(.png))
    }
}
