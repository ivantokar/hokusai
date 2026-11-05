import ArgumentParser
import Hokusai

enum ChromaArgument: String, CaseInsensitiveArgument {
    case automatic, yuv420, yuv444
    var subsampling: ChromaSubsampling {
        switch self {
        case .automatic: .automatic
        case .yuv420: .yuv420
        case .yuv444: .yuv444
        }
    }
}

enum BitDepthArgument: Int, CaseIterable, ExpressibleByArgument {
    case eight = 8, ten = 10, twelve = 12
    var depth: HEIFBitDepth { HEIFBitDepth(rawValue: rawValue) ?? .eight }
}

enum WebPPresetArgument: String, CaseInsensitiveArgument {
    case `default`, picture, photo, drawing, icon, text
    var preset: WebPPreset {
        switch self {
        case .default: .default
        case .picture: .picture
        case .photo: .photo
        case .drawing: .drawing
        case .icon: .icon
        case .text: .text
        }
    }
}

enum HEIFCompressionArgument: String, CaseInsensitiveArgument {
    case hevc, av1
    var compression: HEIFCompression { self == .hevc ? .hevc : .av1 }
}

enum TIFFCompressionArgument: String, CaseInsensitiveArgument {
    case none, jpeg, deflate, packbits, ccittfax4, lzw, webp, zstd, jpeg2000
    var compression: TIFFCompression {
        switch self {
        case .none: .none
        case .jpeg: .jpeg
        case .deflate: .deflate
        case .packbits: .packBits
        case .ccittfax4: .ccittFax4
        case .lzw: .lzw
        case .webp: .webp
        case .zstd: .zstd
        case .jpeg2000: .jpeg2000
        }
    }
}

enum TIFFPredictorArgument: String, CaseInsensitiveArgument {
    case none, horizontal, floatingpoint
    var predictor: TIFFPredictor {
        switch self {
        case .none: .none
        case .horizontal: .horizontal
        case .floatingpoint: .floatingPoint
        }
    }
}

struct JPEGStep: PipelineStep {
    static let name = "jpeg"
    static let summary = "Encode as JPEG (jpeg)."

    @Option(help: "Quality, 1...100.") var quality = JPEGOptions().quality
    @Flag(help: "Progressive scan order.") var progressive = false
    @Option(help: "Chroma subsampling: automatic (default), yuv420 or yuv444.") var chroma = ChromaArgument.automatic
    @Flag(help: "Optimise the Huffman tables.") var optimizeCoding = false

    func apply(to image: Hokusai) throws -> Hokusai {
        var options = JPEGOptions()
        options.quality = quality
        options.progressive = progressive
        options.chromaSubsampling = chroma.subsampling
        options.optimizeCoding = optimizeCoding
        return try image.jpeg(options: options)
    }
}

struct PNGStep: PipelineStep {
    static let name = "png"
    static let summary = "Encode as PNG (png)."

    @Option(help: "Compression level, 0...9.") var compressionLevel = PNGOptions().compressionLevel
    @Flag(help: "Interlaced (Adam7) output.") var interlaced = false
    @Flag(help: "Write an indexed (palette) PNG; needs libimagequant or quantizr.") var palette = false
    @Option(help: "Palette quality, with --palette.") var paletteQuality: Int?
    @Option(help: "Palette dithering, with --palette.") var paletteDither: Double?
    @Option(help: "Palette quantiser effort, with --palette.") var paletteEffort: Int?
    @Option(help: "Palette bit depth, with --palette.") var paletteBitDepth: Int?

    func validate() throws {
        if !palette, paletteQuality != nil || paletteDither != nil || paletteEffort != nil || paletteBitDepth != nil {
            throw ValidationError("--palette-quality, --palette-dither, --palette-effort and --palette-bit-depth need --palette")
        }
    }

    func apply(to image: Hokusai) throws -> Hokusai {
        var options = PNGOptions()
        options.compressionLevel = compressionLevel
        options.interlaced = interlaced
        if palette {
            var colours = PNGPalette()
            if let paletteQuality { colours.quality = paletteQuality }
            if let paletteDither { colours.dither = paletteDither }
            if let paletteEffort { colours.effort = paletteEffort }
            if let paletteBitDepth { colours.bitDepth = paletteBitDepth }
            options.palette = colours
        }
        return try image.png(options: options)
    }
}

struct WebPStep: PipelineStep {
    static let name = "webp"
    static let summary = "Encode as WebP (webp)."

    @Option(help: "Quality, 0...100.") var quality = WebPOptions().quality
    @Option(help: "Encoder effort, 0...6.") var effort = WebPOptions().effort
    @Flag(help: "Lossless.") var lossless = false
    @Option(help: "Quality of the alpha channel, 0...100.") var alphaQuality: Int?
    @Flag(help: "Near-lossless preprocessing.") var nearLossless = false
    @Flag(help: "Smart chroma subsampling.") var smartSubsample = false
    @Option(help: "Preset: default, picture, photo, drawing, icon or text.") var preset = WebPPresetArgument.default

    func apply(to image: Hokusai) throws -> Hokusai {
        var options = WebPOptions()
        options.quality = quality
        options.effort = effort
        options.lossless = lossless
        if let alphaQuality { options.alphaQuality = alphaQuality }
        options.nearLossless = nearLossless
        options.smartSubsample = smartSubsample
        options.preset = preset.preset
        return try image.webp(options: options)
    }
}

struct AVIFStep: PipelineStep {
    static let name = "avif"
    static let summary = "Encode as AVIF (avif)."

    @Option(help: "Quality, 0...100.") var quality = AVIFOptions().quality
    @Option(help: "Encoder effort, 0...9.") var effort = AVIFOptions().effort
    @Flag(help: "Lossless.") var lossless = false
    @Option(help: "Bit depth: 8, 10 or 12.") var bitDepth = BitDepthArgument.eight
    @Option(help: "Chroma subsampling: automatic (default), yuv420 or yuv444.") var chroma = ChromaArgument.automatic

    func apply(to image: Hokusai) throws -> Hokusai {
        var options = AVIFOptions()
        options.quality = quality
        options.effort = effort
        options.lossless = lossless
        options.bitDepth = bitDepth.depth
        options.chromaSubsampling = chroma.subsampling
        return try image.avif(options: options)
    }
}

struct HEIFStep: PipelineStep {
    static let name = "heif"
    static let summary = "Encode as HEIF (heif)."

    @Option(help: "Codec: hevc (default) or av1.") var compression = HEIFCompressionArgument.hevc
    @Option(help: "Quality, 0...100.") var quality = HEIFOptions().quality
    @Option(help: "Encoder effort.") var effort = HEIFOptions().effort
    @Flag(help: "Lossless.") var lossless = false
    @Option(help: "Bit depth: 8, 10 or 12.") var bitDepth = BitDepthArgument.eight
    @Option(help: "Chroma subsampling: automatic (default), yuv420 or yuv444.") var chroma = ChromaArgument.automatic

    func apply(to image: Hokusai) throws -> Hokusai {
        var options = HEIFOptions()
        options.compression = compression.compression
        options.quality = quality
        options.effort = effort
        options.lossless = lossless
        options.bitDepth = bitDepth.depth
        options.chromaSubsampling = chroma.subsampling
        return try image.heif(options: options)
    }
}

struct TIFFStep: PipelineStep {
    static let name = "tiff"
    static let summary = "Encode as TIFF (tiff)."

    @Option(help: "none (default), jpeg, deflate, packbits, ccittfax4, lzw, webp, zstd or jpeg2000.") var compression = TIFFCompressionArgument.none
    @Option(help: "Quality for jpeg, webp and jpeg2000 compression.") var quality = TIFFOptions().quality
    @Option(help: "Predictor: none, horizontal or floatingpoint.") var predictor = TIFFPredictorArgument.none
    @Flag(help: "Write a BigTIFF file.") var bigtiff = false
    @Option(help: "Tile width; needs --tile-height.") var tileWidth: Int?
    @Option(help: "Tile height; needs --tile-width.") var tileHeight: Int?
    @Flag(help: "Write a pyramid of resolutions; needs tiles.") var pyramid = false

    func validate() throws {
        if (tileWidth == nil) != (tileHeight == nil) { throw ValidationError("--tile-width and --tile-height go together") }
        if pyramid, tileWidth == nil { throw ValidationError("--pyramid needs --tile-width and --tile-height") }
    }

    func apply(to image: Hokusai) throws -> Hokusai {
        var options = TIFFOptions()
        options.compression = compression.compression
        options.quality = quality
        options.predictor = predictor.predictor
        options.bigTIFF = bigtiff
        if let tileWidth, let tileHeight {
            var tiling = TIFFTiling(width: tileWidth, height: tileHeight)
            tiling.pyramid = pyramid
            options.tiling = tiling
        }
        return try image.tiff(options: options)
    }
}

struct GIFStep: PipelineStep {
    static let name = "gif"
    static let summary = "Encode a single frame as GIF (gif)."

    @Option(help: "Dithering, 0...1.") var dither = GIFOptions().dither
    @Option(help: "Encoder effort.") var effort = GIFOptions().effort
    @Option(help: "Bit depth, 1...8.") var bitDepth = GIFOptions().bitDepth
    @Flag(help: "Interlaced output.") var interlaced = false

    func apply(to image: Hokusai) throws -> Hokusai {
        var options = GIFOptions()
        options.dither = dither
        options.effort = effort
        options.bitDepth = bitDepth
        options.interlaced = interlaced
        return try image.gif(options: options)
    }
}

struct PDFStep: PipelineStep {
    static let name = "pdf"
    static let summary = "Encode as a raster PDF (pdf)."

    @Option(help: "Page size: image (default), a4, letter, or WIDTHxHEIGHT in points.") var pageSize = "image"
    @Flag(help: "Landscape orientation for a4 and letter.") var landscape = false
    @Option(help: "Margin on every side, in points.") var margin = 0.0
    @Option(help: "Where the image sits on the page.") var anchor = GravityArgument.center
    @Option(help: "Page background as r,g,b[,a] (0...255).", transform: ColorParser.parse) var background: Color?
    @Option(help: "Downsample the image to at most this effective resolution.") var maxDpi: Double?

    func validate() throws {
        _ = try size()
        if landscape, !["a4", "letter"].contains(pageSize.lowercased()) { throw ValidationError("--landscape applies to a4 and letter") }
    }

    private func size() throws -> PDFPageSize {
        let orientation: PDFPageOrientation = landscape ? .landscape : .portrait
        switch pageSize.lowercased() {
        case "image": return .image()
        case "a4": return .a4(orientation)
        case "letter": return .letter(orientation)
        case let text:
            let parts = text.split(separator: "x").compactMap { Double($0) }
            guard parts.count == 2, text.split(separator: "x").count == 2 else {
                throw ValidationError("--page-size is image, a4, letter or WIDTHxHEIGHT in points, got '\(pageSize)'")
            }
            return .points(width: parts[0], height: parts[1])
        }
    }

    func apply(to image: Hokusai) throws -> Hokusai {
        try image.pdf(
            pageSize: try size(), margins: PDFMargins(top: margin, leading: margin, bottom: margin, trailing: margin),
            anchor: anchor.gravity, background: background, maxEffectiveDPI: maxDpi)
    }
}

enum MetadataActionArgument: String, CaseInsensitiveArgument {
    case preserve, remove
    var action: MetadataPolicy.Action { self == .preserve ? .preserve : .remove }
}

enum MetadataPresetArgument: String, CaseInsensitiveArgument {
    case `default`, preserveAll = "preserve-all", removeAll = "remove-all"
    var policy: MetadataPolicy {
        switch self {
        case .default: .default
        case .preserveAll: .preserveAll
        case .removeAll: .removeAll
        }
    }
}

struct MetadataPolicyStep: PipelineStep {
    static let name = "metadata-policy"
    static let summary = "Choose which embedded metadata the output keeps (metadataPolicy)."

    @Option(help: "Start from default, preserve-all or remove-all.") var preset = MetadataPresetArgument.default
    @Option(help: "preserve or remove EXIF.") var exif: MetadataActionArgument?
    @Option(help: "preserve or remove the ICC profile.") var icc: MetadataActionArgument?
    @Option(help: "preserve or remove XMP.") var xmp: MetadataActionArgument?
    @Option(help: "preserve or remove IPTC.") var iptc: MetadataActionArgument?
    @Option(help: "preserve or remove other metadata and comments.") var other: MetadataActionArgument?
    @Option(help: "preserve or remove the orientation tag.") var orientation: MetadataActionArgument?
    @Option(help: "preserve or remove the density.") var density: MetadataActionArgument?

    func apply(to image: Hokusai) throws -> Hokusai {
        var policy = preset.policy
        if let exif { policy.exif = exif.action }
        if let icc { policy.icc = icc.action }
        if let xmp { policy.xmp = xmp.action }
        if let iptc { policy.iptc = iptc.action }
        if let other { policy.other = other.action }
        if let orientation { policy.orientation = orientation.action }
        if let density { policy.density = density.action }
        return image.metadataPolicy(policy)
    }
}
