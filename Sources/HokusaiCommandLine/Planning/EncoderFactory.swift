import Hokusai

/// Encoder flags as typed on the command line. Every field is optional so an
/// omitted flag keeps the library's own default for that encoder.
struct EncoderSettings: Equatable {
    var quality: Int?
    var compressionLevel: Int?
    var effort: Int?
    var progressive = false
    var lossless = false
}

/// Builds the public ``Encoder`` for a format from command-line settings.
///
/// It only overrides what was supplied; ranges and combinations are left to
/// Hokusai to validate.
enum EncoderFactory {
    static func encoder(for format: OutputFormatArgument, settings: EncoderSettings) -> Encoder {
        switch format {
        case .jpeg:
            var options = JPEGOptions()
            if let quality = settings.quality { options.quality = quality }
            options.progressive = settings.progressive
            return .jpeg(options)
        case .png:
            var options = PNGOptions()
            if let level = settings.compressionLevel { options.compressionLevel = level }
            options.interlaced = settings.progressive
            return .png(options)
        case .webp:
            var options = WebPOptions()
            if let quality = settings.quality { options.quality = quality }
            if let effort = settings.effort { options.effort = effort }
            options.lossless = settings.lossless
            return .webp(options)
        case .avif:
            var options = AVIFOptions()
            if let quality = settings.quality { options.quality = quality }
            if let effort = settings.effort { options.effort = effort }
            options.lossless = settings.lossless
            return .avif(options)
        case .heif:
            var options = HEIFOptions()
            if let quality = settings.quality { options.quality = quality }
            if let effort = settings.effort { options.effort = effort }
            options.lossless = settings.lossless
            return .heif(options)
        case .tiff:
            var options = TIFFOptions()
            if let quality = settings.quality { options.quality = quality }
            return .tiff(options)
        case .gif:
            var options = GIFOptions()
            if let effort = settings.effort { options.effort = effort }
            options.interlaced = settings.progressive
            return .gif(options)
        case .pdf:
            return .pdf(PDFOptions())
        }
    }
}
