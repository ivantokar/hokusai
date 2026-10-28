import Foundation

// Typed encoder configuration. Every option maps to one libvips saver
// argument; defaults reproduce the libvips default unless a comment says
// otherwise. Raw native values never appear here.

/// Chroma subsampling for lossy encoders.
public enum ChromaSubsampling: Sendable, Hashable {
    /// The encoder decides: subsampled at lower qualities, full resolution at high ones.
    case automatic
    /// 4:2:0, the smaller choice.
    case yuv420
    /// 4:4:4, no subsampling: sharper colour edges, larger files.
    case yuv444
}

/// Bit depth of AVIF and HEIF colour channels.
public enum HEIFBitDepth: Int, Sendable, Hashable {
    case eight = 8
    case ten = 10
    case twelve = 12
}

/// JPEG encoder settings. Quality uses libvips' 0...100 convention.
public struct JPEGOptions: Sendable, Hashable {
    public var quality: Int
    /// Progressive (interlaced) scans.
    public var progressive: Bool
    public var chromaSubsampling: ChromaSubsampling
    /// Computes optimal Huffman tables: slightly smaller files, slower encoding.
    public var optimizeCoding: Bool

    public init(
        quality: Int = 80, progressive: Bool = false,
        chromaSubsampling: ChromaSubsampling = .automatic, optimizeCoding: Bool = false
    ) {
        self.quality = quality
        self.progressive = progressive
        self.chromaSubsampling = chromaSubsampling
        self.optimizeCoding = optimizeCoding
    }
}

/// Palette (indexed) PNG output. It changes the colour representation, so it
/// is opt-in and takes more time than full-colour output.
public struct PNGPalette: Sendable, Hashable {
    /// Quantisation quality, `0...100`.
    public var quality: Int
    /// Dithering amount, `0...1`.
    public var dither: Double
    /// Quantisation effort, `1...10`.
    public var effort: Int
    /// Palette index bit depth: 1, 2, 4 or 8.
    public var bitDepth: Int

    public init(quality: Int = 100, dither: Double = 1, effort: Int = 7, bitDepth: Int = 8) {
        self.quality = quality
        self.dither = dither
        self.effort = effort
        self.bitDepth = bitDepth
    }
}

/// PNG encoder settings. Compression level follows libvips' 0...9 convention.
public struct PNGOptions: Sendable, Hashable {
    public var compressionLevel: Int
    /// Adam7 interlacing: the image appears progressively while loading.
    public var interlaced: Bool
    /// Indexed output; `nil` keeps full colour.
    public var palette: PNGPalette?

    public init(compressionLevel: Int = 6, interlaced: Bool = false, palette: PNGPalette? = nil) {
        self.compressionLevel = compressionLevel
        self.interlaced = interlaced
        self.palette = palette
    }
}

/// The WebP encoder tuning a source type.
public enum WebPPreset: Sendable, Hashable, CaseIterable {
    case `default`, picture, photo, drawing, icon, text
}

/// WebP encoder settings for lossy/lossless output and encoder effort.
public struct WebPOptions: Sendable, Hashable {
    public var quality: Int
    /// CPU effort, `0...6`.
    public var effort: Int
    public var lossless: Bool
    /// Quality of the alpha channel, `0...100`.
    public var alphaQuality: Int
    /// Lossless-looking output through pre-processing, `lossless` stays off.
    public var nearLossless: Bool
    /// Sharper, slower chroma subsampling.
    public var smartSubsample: Bool
    public var preset: WebPPreset

    public init(
        quality: Int = 80, effort: Int = 4, lossless: Bool = false,
        alphaQuality: Int = 100, nearLossless: Bool = false, smartSubsample: Bool = false,
        preset: WebPPreset = .default
    ) {
        self.quality = quality
        self.effort = effort
        self.lossless = lossless
        self.alphaQuality = alphaQuality
        self.nearLossless = nearLossless
        self.smartSubsample = smartSubsample
        self.preset = preset
    }
}

/// AVIF (AV1 in a HEIF container) encoder settings. The codec is always AV1.
public struct AVIFOptions: Sendable, Hashable {
    public var quality: Int
    /// CPU effort, `0...9`.
    public var effort: Int
    public var lossless: Bool
    public var bitDepth: HEIFBitDepth
    public var chromaSubsampling: ChromaSubsampling

    public init(
        quality: Int = 50, effort: Int = 4, lossless: Bool = false,
        bitDepth: HEIFBitDepth = .eight, chromaSubsampling: ChromaSubsampling = .automatic
    ) {
        self.quality = quality
        self.effort = effort
        self.lossless = lossless
        self.bitDepth = bitDepth
        self.chromaSubsampling = chromaSubsampling
    }
}

/// The codec inside a HEIF container.
public enum HEIFCompression: Sendable, Hashable, CaseIterable {
    /// HEVC, the codec behind `.heic` files.
    case hevc
    /// AV1; ``AVIFOptions`` is the same codec with a name of its own.
    case av1
}

/// HEIF encoder settings with an explicit codec. Never inferred from a filename.
public struct HEIFOptions: Sendable, Hashable {
    public var compression: HEIFCompression
    public var quality: Int
    /// CPU effort, `0...9`.
    public var effort: Int
    public var lossless: Bool
    public var bitDepth: HEIFBitDepth
    public var chromaSubsampling: ChromaSubsampling

    public init(
        compression: HEIFCompression = .hevc, quality: Int = 50, effort: Int = 4, lossless: Bool = false,
        bitDepth: HEIFBitDepth = .eight, chromaSubsampling: ChromaSubsampling = .automatic
    ) {
        self.compression = compression
        self.quality = quality
        self.effort = effort
        self.lossless = lossless
        self.bitDepth = bitDepth
        self.chromaSubsampling = chromaSubsampling
    }
}

/// TIFF compression schemes libvips can write.
public enum TIFFCompression: Sendable, Hashable, CaseIterable {
    case none, jpeg, deflate, packBits, ccittFax4, lzw, webp, zstd, jpeg2000
}

/// The predictor applied before deflate, LZW or zstd compression.
public enum TIFFPredictor: Sendable, Hashable, CaseIterable {
    case none, horizontal, floatingPoint
}

/// Tile layout of a TIFF.
public struct TIFFTiling: Sendable, Hashable {
    public var width: Int
    public var height: Int
    /// Adds reduced-resolution levels, for deep-zoom style viewers.
    public var pyramid: Bool

    public init(width: Int = 128, height: Int = 128, pyramid: Bool = false) {
        self.width = width
        self.height = height
        self.pyramid = pyramid
    }
}

/// TIFF encoder settings.
public struct TIFFOptions: Sendable, Hashable {
    public var compression: TIFFCompression
    /// Quality for `jpeg`, `webp` and `jpeg2000` compression, `1...100`.
    public var quality: Int
    public var predictor: TIFFPredictor
    /// Tiled output; `nil` writes strips.
    public var tiling: TIFFTiling?
    /// 64-bit offsets, for files above 4 GB.
    public var bigTIFF: Bool

    public init(
        compression: TIFFCompression = .none, quality: Int = 75, predictor: TIFFPredictor = .horizontal,
        tiling: TIFFTiling? = nil, bigTIFF: Bool = false
    ) {
        self.compression = compression
        self.quality = quality
        self.predictor = predictor
        self.tiling = tiling
        self.bigTIFF = bigTIFF
    }
}

/// Still (single-frame) GIF encoder settings. Animation belongs to multi-page support.
public struct GIFOptions: Sendable, Hashable {
    /// Dithering amount, `0...1`.
    public var dither: Double
    /// Quantisation effort, `1...10`.
    public var effort: Int
    /// Palette bit depth, `1...8`.
    public var bitDepth: Int
    public var interlaced: Bool

    public init(dither: Double = 1, effort: Int = 7, bitDepth: Int = 8, interlaced: Bool = false) {
        self.dither = dither
        self.effort = effort
        self.bitDepth = bitDepth
        self.interlaced = interlaced
    }

    func validate() throws {
        guard dither.isFinite, (0...1).contains(dither) else { throw HokusaiError.invalidOption(name: "dither", reason: "must be in 0...1") }
        guard (1...10).contains(effort) else { throw HokusaiError.invalidOption(name: "effort", reason: "must be in 1...10") }
        guard (1...8).contains(bitDepth) else { throw HokusaiError.invalidOption(name: "bitDepth", reason: "must be in 1...8") }
    }
}
