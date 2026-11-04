import Foundation
import Hokusai
import Testing

/// Output dimensions of resize, extend, rotate and extract against a reference
/// written from the documented meaning, for seeded random sizes and fits (#121).
@Suite struct GeometryPropertyTests {
    private struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
    }

    private func source(_ width: Int, _ height: Int) throws -> Hokusai {
        try Raster(width: width, height: height) { x, y in [UInt8(x % 256), UInt8(y % 256), 90, 255] }.pipeline()
    }

    private func dimensions(_ pipeline: Hokusai) async throws -> (Int, Int) {
        let info = try await pipeline.png().data().info
        return (info.width, info.height)
    }

    @Test func resizeGivesTheDocumentedBoxForEveryFit() async throws {
        var generator = Generator(state: 0x5EED_0001)
        for _ in 0..<150 {
            let sw = Int.random(in: 1...90, using: &generator), sh = Int.random(in: 1...90, using: &generator)
            let w = Int.random(in: 1...120, using: &generator), h = Int.random(in: 1...120, using: &generator)
            let image = try source(sw, sh)
            let label = "\(sw)x\(sh) to \(w)x\(h)"

            for fit in [ResizeFit.cover, .fill, .contain] {
                #expect(try await dimensions(image.resize(width: w, height: h, fit: fit)) == (w, h), "\(fit) \(label)")
            }
            // `inside` keeps the aspect ratio within the box; `outside` covers the box. Each is bounded by
            // the box on one axis and touches it on the other, up to one pixel of rounding.
            let (iw, ih) = try await dimensions(image.resize(width: w, height: h, fit: .inside))
            #expect(iw <= w && ih <= h && (iw == w || ih == h), "inside \(label) gave \(iw)x\(ih)")
            let (ow, oh) = try await dimensions(image.resize(width: w, height: h, fit: .outside))
            #expect(ow >= w && oh >= h && (ow == w || oh == h), "outside \(label) gave \(ow)x\(oh)")

            // One side given: the other follows the aspect ratio, rounded.
            let (wo, woh) = try await dimensions(image.resize(width: w))
            #expect(wo == w && abs(woh - Int((Double(sh) * Double(w) / Double(sw)).rounded())) <= 1, "width only \(label) gave \(wo)x\(woh)")
            let (hoW, ho) = try await dimensions(image.resize(height: h))
            #expect(ho == h && abs(hoW - Int((Double(sw) * Double(h) / Double(sh)).rounded())) <= 1, "height only \(label) gave \(hoW)x\(ho)")
        }
    }

    @Test func withoutEnlargementNeverGrowsTheImage() async throws {
        var generator = Generator(state: 0x5EED_0002)
        for _ in 0..<100 {
            let sw = Int.random(in: 1...80, using: &generator), sh = Int.random(in: 1...80, using: &generator)
            let w = Int.random(in: 1...160, using: &generator), h = Int.random(in: 1...160, using: &generator)
            let (rw, rh) = try await dimensions(source(sw, sh).resize(width: w, height: h, fit: .inside, withoutEnlargement: true))
            #expect(rw <= sw && rh <= sh, "\(sw)x\(sh) within \(w)x\(h) grew to \(rw)x\(rh)")
        }
    }

    @Test func extendAddsExactlyTheRequestedBorders() async throws {
        var generator = Generator(state: 0x5EED_0003)
        for _ in 0..<100 {
            let sw = Int.random(in: 1...60, using: &generator), sh = Int.random(in: 1...60, using: &generator)
            let top = Int.random(in: 0...20, using: &generator), bottom = Int.random(in: 0...20, using: &generator)
            let left = Int.random(in: 0...20, using: &generator), right = Int.random(in: 0...20, using: &generator)
            let result = try await dimensions(source(sw, sh).extend(top: top, left: left, bottom: bottom, right: right))
            #expect(result == (sw + left + right, sh + top + bottom), "\(sw)x\(sh) + \(top)/\(bottom)/\(left)/\(right)")
        }
    }

    @Test func quarterTurnsSwapTheAxesAndHalfTurnsKeepThem() async throws {
        var generator = Generator(state: 0x5EED_0004)
        for _ in 0..<60 {
            let sw = Int.random(in: 1...70, using: &generator), sh = Int.random(in: 1...70, using: &generator)
            let image = try source(sw, sh)
            for degrees in [0.0, 90, 180, 270, -90, 360, 450] {
                let (rw, rh) = try await dimensions(image.rotate(by: degrees))
                let swapped = Int(abs(degrees) / 90) % 2 == 1
                #expect((rw, rh) == (swapped ? (sh, sw) : (sw, sh)), "\(sw)x\(sh) rotated by \(degrees) gave \(rw)x\(rh)")
            }
        }
    }

    @Test func extractGivesTheRequestedWindow() async throws {
        var generator = Generator(state: 0x5EED_0005)
        for _ in 0..<100 {
            let sw = Int.random(in: 2...80, using: &generator), sh = Int.random(in: 2...80, using: &generator)
            let x = Int.random(in: 0..<sw, using: &generator), y = Int.random(in: 0..<sh, using: &generator)
            let w = Int.random(in: 1...(sw - x), using: &generator), h = Int.random(in: 1...(sh - y), using: &generator)
            #expect(try await dimensions(source(sw, sh).extract(x: x, y: y, width: w, height: h)) == (w, h), "\(sw)x\(sh) at \(x),\(y) \(w)x\(h)")
        }
    }
}
