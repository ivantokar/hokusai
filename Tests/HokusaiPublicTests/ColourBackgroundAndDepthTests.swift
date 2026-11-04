import Foundation
import Hokusai
import Testing

/// #111, findings 9 and 10: a colour given to an operation must mean the same
/// colour whichever colour model or bit depth the image has.
@Suite struct ColourBackgroundAndDepthTests {
    // MARK: - CMYK backgrounds

    private func cmyk() throws -> Hokusai { try Hokusai(data: fixtureData(named: "cmyk", ext: "jpg")) }

    /// The corner is padding in each of these, so it shows the background.
    private func paddedCorners(_ background: Color) throws -> [(String, Hokusai)] {
        let image = try cmyk()
        return [
            ("extend", try image.extend(to: ImageSize(width: 56, height: 56), background: background)),
            ("rotate", try image.rotate(by: 33, background: background)),
            ("contain", try image.resize(width: 56, height: 30, fit: .contain, background: background)),
            ("affine", try image.affine(AffineMatrix(a: 0.9, b: 0.2, c: -0.2, d: 0.9), edges: .background(background))),
        ]
    }

    @Test func aWhiteBackgroundOnACMYKImageIsWhite() async throws {
        for (name, pipeline) in try paddedCorners(.white) {
            let corner = try await rasterize(pipeline).pixel(0, 0)
            #expect(corner[0] >= 250 && corner[1] >= 250 && corner[2] >= 250, "\(name): \(corner)")
        }
    }

    @Test func aRedBackgroundOnACMYKImageIsRed() async throws {
        for (name, pipeline) in try paddedCorners(Color(red: 1, green: 0, blue: 0)) {
            let corner = try await rasterize(pipeline).pixel(0, 0)
            #expect(corner[0] >= 200 && corner[1] <= 80 && corner[2] <= 80, "\(name): \(corner)")
        }
    }

    @Test func aMidGreyBackgroundOnACMYKImageIsMidGrey() async throws {
        for (name, pipeline) in try paddedCorners(Color(red: 0.5, green: 0.5, blue: 0.5)) {
            let corner = try await rasterize(pipeline).pixel(0, 0)
            #expect(corner[0...2].allSatisfy { (110...160).contains($0) }, "\(name): \(corner)")
        }
    }

    // MARK: - 16-bit effects

    /// 16-bit RGB TIFF, little-endian, uncompressed.
    private func tiff16(width: Int, height: Int, _ pixel: (Int, Int) -> [Int]) -> Data {
        var data = Data()
        func u16(_ value: Int) { data.append(contentsOf: [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]) }
        func u32(_ value: Int) { u16(value & 0xFFFF); u16((value >> 16) & 0xFFFF) }
        func entry(_ tag: Int, _ type: Int, _ count: Int, _ value: Int) { u16(tag); u16(type); u32(count); u32(value) }
        let entries = 9
        let arrayOffset = 8 + 2 + entries * 12 + 4
        data.append(contentsOf: [0x49, 0x49, 42, 0]); u32(8); u16(entries)
        entry(256, 4, 1, width); entry(257, 4, 1, height); entry(258, 3, 3, arrayOffset)
        entry(259, 3, 1, 1); entry(262, 3, 1, 2); entry(273, 4, 1, arrayOffset + 6)
        entry(277, 3, 1, 3); entry(278, 4, 1, height); entry(279, 4, 1, width * height * 6)
        u32(0)
        for _ in 0..<3 { u16(16) }
        for y in 0..<height { for x in 0..<width { for value in pixel(x, y) { u16(value) } } }
        return data
    }

    /// The same picture at both depths: every 16-bit sample is the 8-bit sample times 257.
    private func pictures() throws -> (wide: Hokusai, narrow: Hokusai) {
        func sample(_ x: Int, _ y: Int) -> [Int] { [40 + x * 10, 150 - y * 5 + x, 220 - x * 8] }
        let wide = try Hokusai(data: tiff16(width: 16, height: 16) { x, y in sample(x, y).map { $0 * 257 } })
        let narrow = try Hokusai(data: tiffData(Raster(width: 16, height: 16) { x, y in sample(x, y).map(UInt8.init) + [255] }))
        return (wide, narrow)
    }

    private static let effects: [(name: String, apply: @Sendable (Hokusai) throws -> Hokusai)] = [
        ("modulate", { try $0.modulate() }),
        ("modulate brightness", { try $0.modulate(brightness: 1.2) }),
        ("modulate saturation", { try $0.modulate(saturation: 0.5) }),
        ("modulate hue", { try $0.modulate(hue: 30) }),
        ("clahe", { try $0.clahe() }),
        ("normalize", { try $0.normalize() }),
        ("normalize percentiles", { try $0.normalize(lower: 5, upper: 95) }),
        ("gamma", { try $0.gamma(2.2) }),
        ("negate", { try $0.negate() }),
        ("grayscale", { try $0.grayscale() }),
        ("tint", { try $0.tint(Color(red: 1, green: 0.5, blue: 0)) }),
        ("threshold", { try $0.threshold(100) }),
        ("threshold colour", { try $0.threshold(100, grayscale: false) }),
        ("blur", { try $0.blur(sigma: 1) }),
        ("sharpen", { try $0.sharpen(sigma: 1) }),
        ("median", { try $0.median(size: 3) }),
        ("resize", { try $0.resize(width: 8) }),
        ("rotate", { try $0.rotate(by: 33, background: .white) }),
        ("extend", { try $0.extend(top: 4, mode: .background(Color(red: 1, green: 0, blue: 0))) }),
    ]

    @Test(arguments: effects.map(\.name))
    func anEffectGivesTheSamePictureAt16BitAnd8Bit(name: String) async throws {
        let effect = try #require(Self.effects.first { $0.name == name })
        let (wide, narrow) = try pictures()
        let r16 = try await rasterize(effect.apply(wide)), r8 = try await rasterize(effect.apply(narrow))
        #expect((r16.width, r16.height) == (r8.width, r8.height))
        let worst = zip(r16.pixels, r8.pixels).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(worst <= 2, "\(name): the largest difference between the 16-bit and the 8-bit result is \(worst)")
    }
    // MARK: - CLAHE equalises lightness (#71)

    private func hue(_ pixel: [UInt8]) -> Double {
        let r = Double(pixel[0]), g = Double(pixel[1]), b = Double(pixel[2])
        return atan2(3.0.squareRoot() * (g - b), 2 * r - g - b) * 180 / .pi
    }

    @Test func claheKeepsTheHueOfASaturatedColour() async throws {
        // One hue at many lightnesses: equalising R, G and B separately would drift it.
        let source = try Raster(width: 48, height: 48) { x, y in
            let level = 0.35 + 0.65 * Double(x) / 47 * (0.8 + 0.2 * Double(y % 5) / 4)
            return [UInt8(230 * level), UInt8(110 * level), UInt8(30 * level), 255]
        }.pipeline()
        let before = try await rasterize(source)
        let after = try await rasterize(source.clahe(width: 8, height: 8, maxSlope: 3))
        var worst = 0.0
        for x in stride(from: 4, to: 44, by: 4) {
            let a = before.pixel(x, 24), b = after.pixel(x, 24)
            guard b[0] > 40, a[0] > 40 else { continue }   // hue is unstable near black
            worst = max(worst, abs(hue(a) - hue(b)))
        }
        #expect(worst < 8, "the hue moved by up to \(worst) degrees")
    }

    @Test func claheKeepsAlpha() async throws {
        let source = try Raster(width: 24, height: 24) { x, y in
            [UInt8(60 + x * 5), UInt8(80 + y * 3), 120, UInt8(40 + x * 8)]
        }.pipeline()
        let before = try await rasterize(source)
        let after = try await rasterize(source.clahe(width: 4, height: 4, maxSlope: 3))
        #expect(zip(before.pixels.enumerated(), after.pixels).allSatisfy { $0.0.offset % 4 != 3 || $0.0.element == $0.1 })
    }

    @Test func claheOnA16BitImageGivesTheSamePictureAsOn8Bit() async throws {
        let (wide, narrow) = try pictures()
        let r16 = try await rasterize(wide.clahe(width: 4, height: 4, maxSlope: 3))
        let r8 = try await rasterize(narrow.clahe(width: 4, height: 4, maxSlope: 3))
        let worst = zip(r16.pixels, r8.pixels).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(worst <= 2, "largest difference \(worst)")
    }
}
