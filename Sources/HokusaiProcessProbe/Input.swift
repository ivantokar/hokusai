import Foundation
import Hokusai

// Not in main.swift: Swift 6.0 crashes lowering the captures of a function declared there
// when another file calls it (the helpers here are used by Boundary.swift).
func report(_ pairs: KeyValuePairs<String, Any>) {
    for (key, value) in pairs { print("\(key)=\(value)") }
}

/// The name of the error case, which is what callers branch on.
func category(_ error: Error) -> String {
    if error is CancellationError { return "cancelled" }
    switch error as? HokusaiError {
    case .invalidInput: return "invalidInput"
    case .invalidOption: return "invalidOption"
    case .unsupported: return "unsupported"
    case .decode: return "decode"
    case .transform: return "transform"
    case .encode: return "encode"
    case .io: return "io"
    case .resource(let failure): return failure.kind == .queuedEvaluations ? "queueFull" : "resource"
    case .runtime: return "runtime"
    case nil: return "other"
    }
}

/// An uncompressed RGB TIFF, so the probe needs no encoder of its own.
func tiff(width: Int, height: Int) -> Data {
    var data = Data()
    func u16(_ value: Int) { data.append(contentsOf: [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]) }
    func u32(_ value: Int) { u16(value & 0xFFFF); u16((value >> 16) & 0xFFFF) }
    func entry(_ tag: Int, _ type: Int, _ count: Int, _ value: Int) { u16(tag); u16(type); u32(count); u32(value) }
    let entries = 9
    let arrayOffset = 8 + 2 + entries * 12 + 4
    let pixelOffset = arrayOffset + 6
    data.append(contentsOf: [0x49, 0x49, 42, 0])
    u32(8)
    u16(entries)
    entry(256, 4, 1, width)
    entry(257, 4, 1, height)
    entry(258, 3, 3, arrayOffset)
    entry(259, 3, 1, 1)
    entry(262, 3, 1, 2)
    entry(273, 4, 1, pixelOffset)
    entry(277, 3, 1, 3)
    entry(278, 4, 1, height)
    entry(279, 4, 1, width * height * 3)
    u32(0)
    for _ in 0..<3 { u16(8) }
    for y in 0..<height { for x in 0..<width { data.append(contentsOf: [UInt8(x % 256), UInt8(y % 256), UInt8((x + y) % 256)]) } }
    return data
}
