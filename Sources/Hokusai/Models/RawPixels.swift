import Foundation

/// The memory layout of raw pixels: how many channels, and how wide each sample is.
///
/// Samples are interleaved (`RGBRGB…`), unsigned, with no padding between
/// pixels. Colour channels come first and alpha, when present, comes last.
/// 16-bit samples use the machine's byte order, which is little-endian on every
/// platform Hokusai supports. Colour is sRGB, and grey is the same transfer
/// curve with one channel; Hokusai applies no colour profile to raw pixels.
///
/// | Format | Channels | Bytes per pixel |
/// | --- | --- | --- |
/// | ``gray8`` | grey | 1 |
/// | ``grayAlpha8`` | grey, alpha | 2 |
/// | ``rgb8`` | red, green, blue | 3 |
/// | ``rgba8`` | red, green, blue, alpha | 4 |
/// | ``gray16`` | grey | 2 |
/// | ``grayAlpha16`` | grey, alpha | 4 |
/// | ``rgb16`` | red, green, blue | 6 |
/// | ``rgba16`` | red, green, blue, alpha | 8 |
public enum RawPixelFormat: Sendable, Hashable, CaseIterable {
    case gray8
    case grayAlpha8
    case rgb8
    case rgba8
    case gray16
    case grayAlpha16
    case rgb16
    case rgba16

    /// The number of interleaved channels per pixel, alpha included.
    public var channels: Int {
        switch self {
        case .gray8, .gray16: 1
        case .grayAlpha8, .grayAlpha16: 2
        case .rgb8, .rgb16: 3
        case .rgba8, .rgba16: 4
        }
    }

    /// The width of one sample in bytes: 1 or 2.
    public var bytesPerChannel: Int {
        switch self {
        case .gray8, .grayAlpha8, .rgb8, .rgba8: 1
        case .gray16, .grayAlpha16, .rgb16, .rgba16: 2
        }
    }

    /// The size of one pixel in bytes.
    public var bytesPerPixel: Int { channels * bytesPerChannel }

    /// Whether the last channel is alpha.
    public var hasAlpha: Bool {
        switch self {
        case .grayAlpha8, .rgba8, .grayAlpha16, .rgba16: true
        default: false
        }
    }

    /// Whether the colour channels are grey rather than red, green and blue.
    public var isGray: Bool { channels <= 2 }

    /// The bits in one sample: 8 or 16.
    public var bitDepth: Int { bytesPerChannel * 8 }
}

/// Raw pixels produced by ``Hokusai/raw(_:premultiplied:background:)``.
///
/// The layout is fully described by the value, so the bytes cannot be
/// misread: rows run top to bottom, pixels left to right, and ``rowStride``
/// bytes separate the start of one row from the next. Hokusai's own output
/// is tightly packed, so ``rowStride`` equals `width × format.bytesPerPixel`
/// and ``data`` holds exactly ``byteCount`` bytes. The value can be passed
/// back to `Hokusai(raw:)` unchanged to round-trip.
public struct RawImage: Sendable, Hashable {
    public let data: Data
    public let width: Int
    public let height: Int
    public let format: RawPixelFormat
    /// Bytes from the start of one row to the start of the next.
    public let rowStride: Int
    /// Whether the colour channels were multiplied by alpha. Always `false`
    /// for a format without alpha.
    public let premultiplied: Bool

    /// The size of ``data`` in bytes.
    public var byteCount: Int { data.count }

    init(data: Data, width: Int, height: Int, format: RawPixelFormat, premultiplied: Bool) {
        self.data = data
        self.width = width
        self.height = height
        self.format = format
        self.rowStride = width * format.bytesPerPixel
        self.premultiplied = premultiplied
    }
}

/// The geometry of caller-supplied raw pixels, validated once.
struct RawSource: Sendable {
    let data: Data
    let width: Int
    let height: Int
    let format: RawPixelFormat
    let rowStride: Int
    let premultiplied: Bool
    let limits: InputLimits

    /// Checks that `data` is exactly the image the arguments describe.
    ///
    /// Every product is computed with overflow detection, and the limits are
    /// checked before any native call, so a lying header cannot wrap around.
    init(
        data: Data, width: Int, height: Int, format: RawPixelFormat,
        rowStride: Int?, premultiplied: Bool, limits: InputLimits
    ) throws {
        try limits.validate()
        guard width > 0, Int32(exactly: width) != nil else {
            throw HokusaiError.invalidOption(name: "width", reason: "must be in 1...\(Int32.max)")
        }
        guard height > 0, Int32(exactly: height) != nil else {
            throw HokusaiError.invalidOption(name: "height", reason: "must be in 1...\(Int32.max)")
        }
        let (rowBytes, rowOverflow) = width.multipliedReportingOverflow(by: format.bytesPerPixel)
        guard !rowOverflow else {
            throw HokusaiError.invalidOption(name: "width", reason: "a row of this width overflows")
        }
        let stride = rowStride ?? rowBytes
        guard stride >= rowBytes else {
            throw HokusaiError.invalidOption(name: "rowStride", reason: "must be at least \(rowBytes) bytes (width × bytes per pixel)")
        }
        let (total, totalOverflow) = stride.multipliedReportingOverflow(by: height)
        guard !totalOverflow else {
            throw HokusaiError.invalidOption(name: "rowStride", reason: "the image size overflows")
        }
        // Padding after the last row is optional: many producers omit it.
        let minimum = total - (stride - rowBytes)
        guard data.count >= minimum, data.count <= total else {
            let expected = minimum == total ? "\(total)" : "\(minimum) to \(total)"
            throw HokusaiError.invalidInput(
                reason: "raw data is \(data.count) bytes; a \(width)×\(height) \(format) image with a row stride of \(stride) needs \(expected)")
        }
        try limits.checkDecoded(width: width, height: height, channels: format.channels)
        try limits.checkEncodedBytes(data.count)
        self.data = data
        self.width = width
        self.height = height
        self.format = format
        self.rowStride = stride
        self.premultiplied = premultiplied
        self.limits = limits
    }
}
