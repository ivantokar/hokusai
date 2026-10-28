import Foundation
import Hokusai
import Testing

/// 8-bit RGBA pixels in row-major order: the canonical form tests compare.
struct Raster: Equatable {
    var width: Int
    var height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height * 4, "pixel count does not match the dimensions")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Builds a raster from a function of the coordinates.
    init(width: Int, height: Int, _ pixel: (_ x: Int, _ y: Int) -> [UInt8]) {
        var pixels: [UInt8] = []
        pixels.reserveCapacity(width * height * 4)
        for y in 0..<height { for x in 0..<width { pixels += pixel(x, y) } }
        self.init(width: width, height: height, pixels: pixels)
    }

    func pixel(_ x: Int, _ y: Int) -> [UInt8] {
        let start = (y * width + x) * 4
        return Array(pixels[start..<start + 4])
    }

    /// A solid colour.
    static func solid(width: Int, height: Int, _ colour: [UInt8]) -> Raster {
        Raster(width: width, height: height) { _, _ in colour }
    }
}

// MARK: - Comparison

/// How strictly two rasters must agree. Dimensions are always compared exactly.
enum PixelTolerance {
    case exact
    /// No channel of any pixel may differ by more than `maxChannelDelta`.
    case absolute(maxChannelDelta: Int)
    /// Mean absolute error and the worst channel delta must both stay within bounds.
    case aggregate(meanAbsoluteError: Double, maxChannelDelta: Int)
}

struct PixelDifference: CustomStringConvertible {
    var firstMismatch: (x: Int, y: Int, expected: [UInt8], actual: [UInt8])?
    var worstDelta = 0
    var worst: (x: Int, y: Int)?
    var meanAbsoluteError = 0.0
    var sizeMismatch: String?

    var description: String {
        if let sizeMismatch { return sizeMismatch }
        var text = "worst channel delta \(worstDelta)"
        if let worst { text += " at (\(worst.x), \(worst.y))" }
        text += String(format: ", mean absolute error %.4f", meanAbsoluteError)
        if let first = firstMismatch {
            text += "; first mismatch at (\(first.x), \(first.y)): expected \(first.expected), got \(first.actual)"
        }
        return text
    }
}

func difference(_ expected: Raster, _ actual: Raster) -> PixelDifference {
    var result = PixelDifference()
    guard expected.width == actual.width, expected.height == actual.height else {
        result.sizeMismatch = "expected \(expected.width)×\(expected.height), got \(actual.width)×\(actual.height)"
        return result
    }
    var total = 0
    for index in 0..<expected.pixels.count {
        let delta = abs(Int(expected.pixels[index]) - Int(actual.pixels[index]))
        total += delta
        let pixelIndex = index / 4
        let x = pixelIndex % expected.width, y = pixelIndex / expected.width
        if delta > 0, result.firstMismatch == nil {
            result.firstMismatch = (x, y, expected.pixel(x, y), actual.pixel(x, y))
        }
        if delta > result.worstDelta {
            result.worstDelta = delta
            result.worst = (x, y)
        }
    }
    result.meanAbsoluteError = expected.pixels.isEmpty ? 0 : Double(total) / Double(expected.pixels.count)
    return result
}

/// Records an issue that names the first and worst differing pixels.
func expectPixels(
    _ actual: Raster, match expected: Raster, _ tolerance: PixelTolerance = .exact,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let diff = difference(expected, actual)
    let accepted: Bool
    switch tolerance {
    case .exact:
        accepted = diff.sizeMismatch == nil && diff.worstDelta == 0
    case .absolute(let maxDelta):
        accepted = diff.sizeMismatch == nil && diff.worstDelta <= maxDelta
    case .aggregate(let mae, let maxDelta):
        accepted = diff.sizeMismatch == nil && diff.meanAbsoluteError <= mae && diff.worstDelta <= maxDelta
    }
    #expect(accepted, "pixels differ: \(diff)", sourceLocation: sourceLocation)
}

/// True when the two rasters differ in size or content.
func differ(_ first: Raster, _ second: Raster) -> Bool {
    first != second
}

// MARK: - Raster ⇄ TIFF (uncompressed, 8-bit RGBA)

/// An uncompressed little-endian TIFF. It is the one format both easy to
/// write and easy to read without a decoder, so the suite needs no native
/// helper: inputs are built with it and outputs are read back through it.
func tiffData(_ raster: Raster, orientation: Int = 1) -> Data {
    var data = Data()
    func u16(_ value: Int) { data.append(contentsOf: [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]) }
    func u32(_ value: Int) { u16(value & 0xFFFF); u16((value >> 16) & 0xFFFF) }
    func entry(_ tag: Int, type: Int, count: Int, value: Int) { u16(tag); u16(type); u32(count); u32(value) }

    let entries = 11
    let ifdOffset = 8
    let arrayOffset = ifdOffset + 2 + entries * 12 + 4
    let pixelOffset = arrayOffset + 8
    data.append(contentsOf: [0x49, 0x49, 42, 0])
    u32(ifdOffset)
    u16(entries)
    entry(256, type: 4, count: 1, value: raster.width)
    entry(257, type: 4, count: 1, value: raster.height)
    entry(258, type: 3, count: 4, value: arrayOffset)
    entry(259, type: 3, count: 1, value: 1)
    entry(262, type: 3, count: 1, value: 2)
    entry(273, type: 4, count: 1, value: pixelOffset)
    entry(274, type: 3, count: 1, value: orientation)
    entry(277, type: 3, count: 1, value: 4)
    entry(278, type: 4, count: 1, value: raster.height)
    entry(279, type: 4, count: 1, value: raster.pixels.count)
    entry(338, type: 3, count: 1, value: 2)
    u32(0)
    for _ in 0..<4 { u16(8) }
    data.append(contentsOf: raster.pixels)
    return data
}

enum RasterError: Error { case unsupported(String) }

/// Reads an uncompressed 8-bit little-endian TIFF with three or four bands.
func raster(fromTIFF data: Data) throws -> Raster {
    let bytes = [UInt8](data)
    guard bytes.count > 8, bytes[0] == 0x49, bytes[1] == 0x49 else { throw RasterError.unsupported("not a little-endian TIFF") }
    func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
    func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }

    var tags: [Int: [Int]] = [:]
    let ifd = u32(4)
    for index in 0..<u16(ifd) {
        let base = ifd + 2 + index * 12
        let tag = u16(base), type = u16(base + 2), count = u32(base + 4)
        let size = (type == 3 ? 2 : 4) * count
        let location = size <= 4 ? base + 8 : u32(base + 8)
        tags[tag] = (0..<count).map { type == 3 ? u16(location + $0 * 2) : u32(location + $0 * 4) }
    }
    guard let width = tags[256]?.first, let height = tags[257]?.first,
        let bands = tags[277]?.first, let offsets = tags[273], let counts = tags[279],
        tags[259]?.first == 1, tags[258]?.allSatisfy({ $0 == 8 }) == true, bands == 3 || bands == 4
    else { throw RasterError.unsupported("not an uncompressed 8-bit RGB(A) TIFF") }

    var samples: [UInt8] = []
    for (offset, count) in zip(offsets, counts) { samples += bytes[offset..<offset + count] }
    var pixels: [UInt8] = []
    pixels.reserveCapacity(width * height * 4)
    for index in 0..<width * height {
        pixels += samples[index * bands..<index * bands + 3]
        pixels.append(bands == 4 ? samples[index * bands + 3] : 255)
    }
    return Raster(width: width, height: height, pixels: pixels)
}

// MARK: - Pipelines

extension Raster {
    /// A pipeline over this raster, stored as an uncompressed TIFF.
    func pipeline(orientation: Int = 1, options: InputOptions = .init()) throws -> Hokusai {
        try Hokusai(data: tiffData(self, orientation: orientation), options: options)
    }
}

/// Evaluates `pipeline` to canonical pixels: sRGB, 8-bit, RGBA, with output
/// metadata removed so no orientation state is left to interpret.
func rasterize(_ pipeline: Hokusai) async throws -> Raster {
    let encoded = try await pipeline
        .convert(to: .sRGB)
        .ensureAlpha()
        .tiff(compression: .none)
        .metadataPolicy(.removeAll)
        .data()
    return try raster(fromTIFF: encoded.data)
}

/// Pixels of already-encoded bytes in any supported format.
func rasterize(encoded data: Data) async throws -> Raster {
    try await rasterize(Hokusai(data: data))
}

/// A deterministic asymmetric RGBA raster: every pixel is distinct.
func gradient(width: Int, height: Int) -> Raster {
    Raster(width: width, height: height) { x, y in
        [UInt8((x * 255) / max(width - 1, 1)), UInt8((y * 255) / max(height - 1, 1)), UInt8((x * 7 + y * 13) % 256), 255]
    }
}
