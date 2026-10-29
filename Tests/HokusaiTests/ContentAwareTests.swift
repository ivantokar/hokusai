import Foundation
import Testing
@testable import Hokusai

/// Content-aware behaviour is covered in `HokusaiPublicTests`. What stays here
/// needs `makePNG`, which can build the single-band input the public raster
/// helpers (always RGBA) cannot.
@Suite struct ContentAwareTests {
    init() throws { try Hokusai.initialize() }

    @Test func trimHandlesGreyImages() async throws {
        var pixels = [UInt8](repeating: 255, count: 30 * 30)
        for y in 10..<18 { for x in 4..<10 { pixels[y * 30 + x] = 0 } }
        let image = try Hokusai(data: makePNG(width: 30, height: 30, bands: 1, pixels: pixels))

        let plain = try await image.trim().png().data().info
        #expect(plain.width == 6 && plain.height == 8)
        let explicit = try await image.trim(TrimOptions(background: .color(.white))).png().data().info
        #expect(explicit.width == 6 && explicit.height == 8)
    }
}
