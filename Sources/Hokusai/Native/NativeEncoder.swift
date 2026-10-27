import Foundation
import CVips

extension ChromaSubsampling {
    /// 0 automatic, 1 4:2:0, 2 4:4:4, as the shims expect.
    fileprivate var nativeValue: Int32 {
        switch self {
        case .automatic: 0
        case .yuv420: 1
        case .yuv444: 2
        }
    }
}

/// One internal lowering of a typed raster encoder, applied identically to
/// every sink.
///
/// Each case maps a public options value to the native saver exactly once, in
/// ``save(_:to:)``. Memory and file output only differ in the `VipsTarget`
/// handed to that call, so a codec option can never reach one sink and miss
/// the other. PDF is not a libvips saver and has its own path.
enum NativeEncoder {
    case jpeg(JPEGOptions, metadata: MetadataPolicy)
    case png(PNGOptions, metadata: MetadataPolicy)
    case webp(WebPOptions, metadata: MetadataPolicy)
    case avif(AVIFOptions, metadata: MetadataPolicy)
    case heif(HEIFOptions, metadata: MetadataPolicy)
    case tiff(TIFFOptions, metadata: MetadataPolicy)
    case gif(GIFOptions, metadata: MetadataPolicy)

    /// The lowering for `format`, or `nil` for PDF.
    init?(format: OutputFormat, metadata: MetadataPolicy) {
        switch format {
        case .jpeg(let options): self = .jpeg(options, metadata: metadata)
        case .png(let options): self = .png(options, metadata: metadata)
        case .webp(let options): self = .webp(options, metadata: metadata)
        case .avif(let options): self = .avif(options, metadata: metadata)
        case .heif(let options): self = .heif(options, metadata: metadata)
        case .tiff(let options): self = .tiff(options, metadata: metadata)
        case .gif(let options): self = .gif(options, metadata: metadata)
        case .pdf: return nil
        }
    }

    /// The metadata policy this encoder applies.
    var metadata: MetadataPolicy {
        switch self {
        case .jpeg(_, let metadata), .png(_, let metadata), .webp(_, let metadata), .avif(_, let metadata),
             .heif(_, let metadata), .tiff(_, let metadata), .gif(_, let metadata): metadata
        }
    }

    /// The format this encoder produces.
    var imageFormat: ImageFormat {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        case .webp: .webp
        case .avif: .avif
        case .heif: .heif
        case .tiff: .tiff
        case .gif: .gif
        }
    }

    /// Runs the native saver into `target` and returns libvips' result code.
    ///
    /// `keep` is the `VipsForeignKeep` set from ``MetadataPolicy`` lowering;
    /// the image must already be prepared by ``prepareMetadata(of:)``.
    fileprivate func save(_ image: NativeImage, keep: Int32, to target: UnsafeMutablePointer<VipsTarget>) -> Int32 {
        switch self {
        case .jpeg(let options, _):
            return swift_vips_jpegsave_target(
                image.pointer, target, Int32(options.quality), options.progressive ? 1 : 0,
                options.chromaSubsampling.nativeValue, options.optimizeCoding ? 1 : 0, keep)
        case .png(let options, _):
            let palette = options.palette
            return swift_vips_pngsave_target(
                image.pointer, target, Int32(options.compressionLevel), options.interlaced ? 1 : 0,
                palette == nil ? 0 : 1, Int32(palette?.quality ?? 100), palette?.dither ?? 1,
                Int32(palette?.effort ?? 7), Int32(palette?.bitDepth ?? 8), keep)
        case .webp(let options, _):
            return swift_vips_webpsave_target(
                image.pointer, target, Int32(options.quality), options.lossless ? 1 : 0, Int32(options.effort),
                Int32(options.alphaQuality), options.nearLossless ? 1 : 0, options.smartSubsample ? 1 : 0,
                Int32(WebPPreset.allCases.firstIndex(of: options.preset) ?? 0), keep)
        case .avif(let options, _):
            // A target has no filename to infer the codec from, so AV1 is explicit.
            return swift_vips_heifsave_target(
                image.pointer, target, Int32(options.quality), options.lossless ? 1 : 0, Int32(options.effort),
                Int32(options.bitDepth.rawValue), options.chromaSubsampling.nativeValue, keep, 1)
        case .heif(let options, _):
            return swift_vips_heifsave_target(
                image.pointer, target, Int32(options.quality), options.lossless ? 1 : 0, Int32(options.effort),
                Int32(options.bitDepth.rawValue), options.chromaSubsampling.nativeValue, keep,
                options.compression == .av1 ? 1 : 0)
        case .tiff(let options, _):
            return swift_vips_tiffsave_target(
                image.pointer, target, Int32(TIFFCompression.allCases.firstIndex(of: options.compression) ?? 0),
                Int32(options.quality), Int32(TIFFPredictor.allCases.firstIndex(of: options.predictor) ?? 0),
                Int32(options.tiling?.width ?? 0), Int32(options.tiling?.height ?? 0),
                options.tiling?.pyramid == true ? 1 : 0, options.bigTIFF ? 1 : 0, keep)
        case .gif(let options, _):
            return swift_vips_gifsave_target(
                image.pointer, target, options.dither, Int32(options.effort), Int32(options.bitDepth),
                options.interlaced ? 1 : 0, keep)
        }
    }

    /// Applies this encoder's metadata policy to `image`, returning the image to
    /// save and the native `keep` set. Every sink goes through here, so the
    /// policy cannot differ between memory and file output.
    fileprivate func prepareMetadata(of image: NativeImage) throws -> (image: NativeImage, keep: Int32) {
        try metadata.lowered(for: image, format: imageFormat)
    }
}

extension NativeImage {
    /// Encodes into native memory and returns the bytes as owned `Data`.
    ///
    /// The encoded buffer is transferred to the returned `Data` without a copy
    /// and released exactly once, when that `Data` is deallocated.
    func encoded(_ encoder: NativeEncoder) throws -> Data {
        guard let target = swift_vips_memory_target_new() else {
            throw HokusaiError.runtime(.native("encode \(encoder.imageFormat.rawValue)", "could not create an output buffer"))
        }
        defer { g_object_unref(target) }

        let (prepared, keep) = try encoder.prepareMetadata(of: self)
        guard encoder.save(prepared, keep: keep, to: target) == 0 else {
            throw HokusaiError.nativeEncode(encoder.imageFormat.rawValue)
        }

        var length = 0
        guard let bytes = swift_vips_memory_target_steal(target, &length) else {
            throw HokusaiError.nativeEncode(encoder.imageFormat.rawValue)
        }
        guard length >= 0 else {
            g_free(bytes)
            throw HokusaiError.encode(FailureContext(
                operation: "encode \(encoder.imageFormat.rawValue)", reason: "the encoded output has an invalid length"))
        }
        return Data(bytesNoCopy: bytes, count: length, deallocator: .custom { pointer, _ in g_free(pointer) })
    }

    /// Encodes straight into a file at `url` and returns the bytes written.
    ///
    /// Nothing is materialised as `Data`. The file is created when the first
    /// bytes are written, so a failure before any output leaves the
    /// destination untouched. A failure after output began removes the regular
    /// file that was being written rather than leaving a partial image. A
    /// destination that cannot be opened or written fails with
    /// ``HokusaiError/io(url:operation:reason:)``, decided from the system
    /// error code and never from libvips text.
    func write(_ encoder: NativeEncoder, to url: URL) throws -> Int {
        let sink = swift_vips_file_sink_new(url.path)!
        guard let target = swift_vips_file_target_new(sink) else {
            _ = swift_vips_file_sink_finish(sink, 0)
            throw HokusaiError.runtime(.native("encode \(encoder.imageFormat.rawValue)", "could not create an output target"))
        }

        let result: Int32
        do {
            let (prepared, keep) = try encoder.prepareMetadata(of: self)
            result = encoder.save(prepared, keep: keep, to: target)
        } catch {
            g_object_unref(target)
            _ = swift_vips_file_sink_finish(sink, 0)
            throw error
        }
        g_object_unref(target)
        let written = Int(swift_vips_file_sink_written(sink))
        let error = swift_vips_file_sink_finish(sink, result == 0 ? 1 : 0)

        if error != 0 {
            throw HokusaiError.io(url: url, operation: .write, reason: String(cString: strerror(error)))
        }
        guard result == 0 else {
            throw HokusaiError.nativeEncode(encoder.imageFormat.rawValue)
        }
        return written
    }
}
