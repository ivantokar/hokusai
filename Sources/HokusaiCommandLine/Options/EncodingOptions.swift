import ArgumentParser

/// Output format and encoder flags of `convert`. Values are passed to the
/// public typed options unchanged; ranges are validated by Hokusai, not here.
struct EncodingOptions: ParsableArguments {
    @Option(help: "Output format. Optional if the output extension names one.")
    var format: OutputFormatArgument?

    @Option(help: "Quality for lossy formats (JPEG, WebP, AVIF, HEIF, TIFF).")
    var quality: Int?

    @Option(help: "PNG compression level.")
    var compression: Int?

    @Flag(help: "Use progressive/interlaced output when supported.")
    var progressive = false

    @Flag(help: "Remove all metadata, including the ICC profile, orientation, and density. Without it Hokusai's default applies: EXIF, XMP, and IPTC are removed and those three are kept.")
    var stripMetadata = false

    @Flag(help: "Use lossless mode where supported.")
    var lossless = false

    @Option(help: "Encoder effort where supported (WebP, AVIF, HEIF, GIF).")
    var effort: Int?

    var settings: EncoderSettings {
        EncoderSettings(
            quality: quality, compressionLevel: compression, effort: effort,
            progressive: progressive, lossless: lossless)
    }
}
