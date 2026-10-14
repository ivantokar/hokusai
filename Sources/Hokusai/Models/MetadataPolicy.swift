import Foundation

/// What encoded output keeps of the source's embedded metadata.
///
/// This is output retention only. It is separate from ``ImageMetadata``, which
/// reports what the *source* contained, and from pixel statistics. The policy
/// is part of the terminal configuration, not an image operation: the last
/// ``Hokusai/metadataPolicy(_:)`` wins, and a composite layer's policy is
/// ignored.
///
/// The default is privacy-minimising yet rendering-safe: descriptive and
/// identifying blocks (EXIF, XMP, IPTC, comments) are removed, while the ICC
/// profile, the orientation tag, and the pixel density, which affect how the
/// image displays, are kept.
///
/// ```swift
/// try image.jpeg().metadataPolicy(.preserveAll)
/// try image.webp().metadataPolicy(MetadataPolicy(icc: .remove))
/// ```
///
/// Retention is limited by the target format. A family a format cannot carry
/// is simply absent from its output (for example, WebP has no IPTC block and no
/// density), and the README lists what each format keeps.
public struct MetadataPolicy: Sendable, Equatable {
    /// Whether a metadata family is carried into the output.
    public enum Action: Sendable, Equatable {
        case preserve
        case remove
    }

    /// Camera and capture details, GPS position, timestamps, and descriptions.
    /// With ``orientation`` preserved, removing EXIF still leaves a minimal EXIF
    /// block holding the orientation and the structural entries libvips writes
    /// itself (pixel dimensions, resolution, versions).
    public var exif: Action

    /// The embedded colour profile. Keeping it is a retention choice, not a
    /// colour conversion: no profile is applied, attached, or changed.
    public var icc: Action

    /// The XMP packet.
    public var xmp: Action

    /// The IPTC block.
    public var iptc: Action

    /// Other embedded metadata such as comments.
    public var other: Action

    /// The EXIF/TIFF orientation tag. `.remove` deletes the tag **without
    /// rotating pixels**; use `autoOrient()` to apply orientation. Removing the
    /// tag from an image that was not auto-oriented changes how it displays.
    /// If EXIF is kept in full, EXIF cannot omit the entry, so `.remove` writes
    /// the neutral value "up". AVIF and HEIF store orientation as a container
    /// rotation instead of a tag, so a reader applies it and reports no tag;
    /// older libvips builds write only the EXIF tag, which those readers
    /// ignore, so call `autoOrient()` before encoding AVIF for such builds.
    public var orientation: Action

    /// The pixel density. `.remove` stops the source's resolution from being
    /// carried over; the output records the encoder's own default instead,
    /// because most formats always write some resolution (one pixel per
    /// millimetre, or 72 DPI where a JPEG has no EXIF block to hold it) and
    /// none can store "none". Formats without a density, such as WebP and
    /// AVIF, are unaffected.
    public var density: Action

    public init(
        exif: Action = .remove,
        icc: Action = .preserve,
        xmp: Action = .remove,
        iptc: Action = .remove,
        other: Action = .remove,
        orientation: Action = .preserve,
        density: Action = .preserve
    ) {
        self.exif = exif
        self.icc = icc
        self.xmp = xmp
        self.iptc = iptc
        self.other = other
        self.orientation = orientation
        self.density = density
    }

    /// Removes descriptive and identifying metadata, keeps the ICC profile,
    /// orientation, and density.
    public static let `default` = MetadataPolicy()

    /// Keeps everything the target format can carry.
    public static let preserveAll = MetadataPolicy(
        exif: .preserve, icc: .preserve, xmp: .preserve, iptc: .preserve,
        other: .preserve, orientation: .preserve, density: .preserve)

    /// Removes everything, including the ICC profile, orientation tag, and
    /// density. Pixels are untouched, so an image that relied on a profile or
    /// orientation tag can display differently.
    public static let removeAll = MetadataPolicy(
        exif: .remove, icc: .remove, xmp: .remove, iptc: .remove,
        other: .remove, orientation: .remove, density: .remove)
}
