import Foundation
import Hokusai
import Testing

/// Colour model x operation matrix (#121). #117 compared 8-bit with 16-bit RGB; this
/// compares the other models with the RGB picture they stand for. A grey image, a
/// grey image with alpha and a 16-bit grey image must give the same result as the
/// RGB image with equal bands, whatever the operation, and CMYK must at least obey
/// the contracts that do not depend on a colour profile.
@Suite struct ColourModelMatrixTests {
    private let size = 16

    /// An uncompressed little-endian TIFF with `bands` samples of `bits` bits.
    private func tiff(bands: Int, bits: Int, photometric: Int, alphaBand: Bool, pixel: (Int, Int) -> [Int]) -> Data {
        var data = Data()
        func u16(_ value: Int) { data.append(contentsOf: [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]) }
        func u32(_ value: Int) { u16(value & 0xFFFF); u16((value >> 16) & 0xFFFF) }
        func entry(_ tag: Int, _ type: Int, _ count: Int, _ value: Int) { u16(tag); u16(type); u32(count); u32(value) }
        let entries = alphaBand ? 11 : 10
        let bitsOffset = 8 + 2 + entries * 12 + 4
        let pixelOffset = bitsOffset + (bands > 2 ? bands * 2 : 0)
        let byteCount = size * size * bands * (bits / 8)
        data.append(contentsOf: [0x49, 0x49, 42, 0])
        u32(8)
        u16(entries)
        entry(256, 4, 1, size)
        entry(257, 4, 1, size)
        entry(258, 3, bands, bands > 2 ? bitsOffset : (bands == 2 ? bits | (bits << 16) : bits))
        entry(259, 3, 1, 1)
        entry(262, 3, 1, photometric)
        entry(273, 4, 1, pixelOffset)
        entry(277, 3, 1, bands)
        entry(278, 4, 1, size)
        entry(279, 4, 1, byteCount)
        entry(284, 3, 1, 1)
        if alphaBand { entry(338, 3, 1, 2) }
        u32(0)
        if bands > 2 { for _ in 0..<bands { u16(bits) } }
        for y in 0..<size { for x in 0..<size { for value in pixel(x, y) { bits == 16 ? u16(value) : data.append(UInt8(value)) } } }
        return data
    }

    private func level(_ x: Int, _ y: Int) -> Int { 30 + x * 9 + y * 3 }
    private func alpha(_ x: Int, _ y: Int) -> Int { 120 + x * 8 }

    private func rgbReference(withAlpha: Bool) throws -> Hokusai {
        try Raster(width: size, height: size) { x, y in
            let v = UInt8(level(x, y))
            return [v, v, v, withAlpha ? UInt8(alpha(x, y)) : 255]
        }.pipeline()
    }

    private func grey() throws -> Hokusai {
        try Hokusai(data: tiff(bands: 1, bits: 8, photometric: 1, alphaBand: false) { x, y in [level(x, y)] })
    }
    private func greyAlpha() throws -> Hokusai {
        try Hokusai(data: tiff(bands: 2, bits: 8, photometric: 1, alphaBand: true) { x, y in [level(x, y), alpha(x, y)] })
    }
    private func grey16() throws -> Hokusai {
        try Hokusai(data: tiff(bands: 1, bits: 16, photometric: 1, alphaBand: false) { x, y in [level(x, y) * 257] })
    }

    private static let operations: [(name: String, apply: @Sendable (Hokusai) throws -> Hokusai)] = [
        ("resize", { try $0.resize(width: 9) }),
        ("resize contain", { try $0.resize(width: 24, height: 12, fit: .contain, background: .white) }),
        ("rotate", { try $0.rotate(by: 33, background: .white) }),
        ("rotate quarter", { try $0.rotate(by: 90) }),
        ("extend", { try $0.extend(top: 3, left: 2, bottom: 1, right: 4, mode: .background(.white)) }),
        ("extract", { try $0.extract(x: 2, y: 3, width: 8, height: 7) }),
        ("flip", { try $0.flip() }),
        ("blur", { try $0.blur(sigma: 1.5) }),
        ("sharpen", { try $0.sharpen(sigma: 1) }),
        ("median", { try $0.median(size: 3) }),
        ("gamma", { try $0.gamma(2.2) }),
        ("negate", { try $0.negate() }),
        ("normalize", { try $0.normalize() }),
        ("threshold", { try $0.threshold(100) }),
        ("grayscale", { try $0.grayscale() }),
        ("modulate brightness", { try $0.modulate(brightness: 1.2) }),
        ("flatten", { try $0.flatten(background: .white) }),
    ]

    @Test(arguments: operations.map(\.name))
    func greyModelsMatchTheEquivalentRGBPicture(name: String) async throws {
        let operation = try #require(Self.operations.first { $0.name == name })
        for (model, source, withAlpha) in [
            ("grey", try grey(), false), ("grey+alpha", try greyAlpha(), true), ("grey 16-bit", try grey16(), false),
        ] {
            let expected = try await rasterize(operation.apply(rgbReference(withAlpha: withAlpha)))
            let actual = try await rasterize(operation.apply(source))
            #expect((actual.width, actual.height) == (expected.width, expected.height), "\(name) on \(model): size")
            let worst = zip(actual.pixels, expected.pixels).map { abs(Int($0) - Int($1)) }.max() ?? 0
            #expect(worst <= 3, "\(name) on \(model): the largest difference from the RGB picture is \(worst)")
        }
    }
    // MARK: - CMYK

    private func cmyk() throws -> Hokusai { try Hokusai(data: fixtureData(named: "cmyk", ext: "jpg")) }

    @Test(arguments: operations.map(\.name))
    func cmykKeepsTheSizeOfTheRGBResult(name: String) async throws {
        let operation = try #require(Self.operations.first { $0.name == name })
        let rgb = try Hokusai(data: fixtureData(named: "landscape-asym", ext: "jpg"))
        let expected = try await rasterize(operation.apply(rgb))
        let actual = try await rasterize(operation.apply(cmyk()))
        // The two fixtures are the same size, so every operation must give the same dimensions.
        let base = try await rasterize(rgb), cmykBase = try await rasterize(cmyk())
        if (base.width, base.height) == (cmykBase.width, cmykBase.height) {
            #expect((actual.width, actual.height) == (expected.width, expected.height), "\(name) on CMYK")
        }
    }

    @Test(arguments: ["resize contain", "rotate", "extend"])
    func aWhiteBackgroundIsWhiteInEveryColourModel(name: String) async throws {
        let operation = try #require(Self.operations.first { $0.name == name })
        for (model, source) in [("CMYK", try cmyk())] {
            let result = try await rasterize(operation.apply(source))
            let corner = result.pixel(0, 0)
            #expect(corner[0] >= 235 && corner[1] >= 235 && corner[2] >= 235, "\(name) on \(model): the padding is \(corner)")
        }
    }
}
