import Foundation

/// What a pipeline's root source reported when it was opened.
///
/// `ImageMetadata` describes the **source**, never the transformed pipeline:
/// `image.metadata()` and `image.resize(width: 400).metadata()` return the same
/// value, and a composite pipeline reports only its base source (inspect an
/// overlay's own `Hokusai` value to see its metadata). For the dimensions,
/// byte size, and format of what a pipeline produces, use ``OutputInfo``.
///
/// Fields are the stored header facts: `width` and `height` are *not* swapped
/// for EXIF orientation (see ``orientedSize``). A pixel interpretation such as
/// ``PixelInterpretation/sRGB`` says how the stored values are read; it does
/// not mean an embedded ICC profile was applied.
public struct ImageMetadata: Sendable, Equatable {
    /// The source's format, or `nil` when it cannot be identified reliably.
    ///
    /// Identified from the loader libvips used, not from a file name. AVIF and
    /// HEIC share one loader and are told apart by their HEIF compression.
    public var format: ImageFormat?

    /// Stored width in pixels of the selected page, before orientation.
    public var width: Int

    /// Stored height in pixels of the selected page, before orientation.
    public var height: Int

    /// The EXIF/TIFF orientation, or `nil` when absent or not one of 1...8.
    ///
    /// Some loaders (modern HEIF, for example) apply the container's rotation
    /// themselves and then expose no tag, so `nil` does not prove the stored
    /// pixels were never rotated.
    public var orientation: ImageOrientation?

    /// How the stored pixels are laid out and interpreted.
    public var pixel: PixelMetadata

    /// Pixel density in dots per inch, or `nil` when the source records none.
    ///
    /// libvips reports 1 pixel/mm when a file has no resolution; that default
    /// is treated as "not recorded" rather than as 25.4 DPI.
    public var density: ImageDensity?

    /// The unit the source preferred for its resolution, when it records one.
    public var densityUnit: ResolutionUnit?

    /// Page and document facts. `pages.count > 1` means multi-page, not animated.
    public var pages: PageMetadata

    /// Animation facts, present only when the source is actually animated.
    public var animation: AnimationMetadata?

    /// The size of the encoded source in bytes: exact for `Data`, the file size
    /// for a local file, and `nil` when there is no encoded source.
    public var sourceByteSize: Int?

    /// Whether the source is progressive (JPEG) or interlaced (PNG), when the
    /// loader reports it reliably; `nil` for other formats.
    public var isProgressive: Bool?

    /// JPEG chroma subsampling in J:a:b notation such as `"4:2:0"`, when reported.
    public var chromaSubsampling: String?

    /// The raw EXIF block, starting with `Exif\0\0`.
    public var exif: Data?

    /// The raw embedded ICC profile.
    public var iccProfile: Data?

    /// The raw XMP packet.
    public var xmp: Data?

    /// The raw IPTC block exactly as libvips exposes it: the Photoshop
    /// "image resource" block that carries the IPTC records.
    public var iptc: Data?

    public init(
        format: ImageFormat? = nil,
        width: Int,
        height: Int,
        orientation: ImageOrientation? = nil,
        pixel: PixelMetadata,
        density: ImageDensity? = nil,
        densityUnit: ResolutionUnit? = nil,
        pages: PageMetadata = PageMetadata(),
        animation: AnimationMetadata? = nil,
        sourceByteSize: Int? = nil,
        isProgressive: Bool? = nil,
        chromaSubsampling: String? = nil,
        exif: Data? = nil,
        iccProfile: Data? = nil,
        xmp: Data? = nil,
        iptc: Data? = nil
    ) {
        self.format = format
        self.width = width
        self.height = height
        self.orientation = orientation
        self.pixel = pixel
        self.density = density
        self.densityUnit = densityUnit
        self.pages = pages
        self.animation = animation
        self.sourceByteSize = sourceByteSize
        self.isProgressive = isProgressive
        self.chromaSubsampling = chromaSubsampling
        self.exif = exif
        self.iccProfile = iccProfile
        self.xmp = xmp
        self.iptc = iptc
    }

    /// The displayed size after applying `orientation`: width and height swap
    /// only for the orientations that rotate a quarter turn.
    public var orientedSize: ImageSize {
        orientation?.swapsDimensions == true
            ? ImageSize(width: height, height: width)
            : ImageSize(width: width, height: height)
    }

    /// Whether the source is an animation, as established by its animation
    /// metadata and never by its page count alone.
    public var isAnimated: Bool { animation != nil }

    /// The XMP packet as text, when it is valid UTF-8. The raw bytes in
    /// ``xmp`` remain authoritative.
    public var xmpString: String? {
        xmp.flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// EXIF/TIFF orientation, values 1 through 8, named for the stored image's
/// relation to the displayed one.
public enum ImageOrientation: Int, Sendable, Equatable, CaseIterable {
    case up = 1
    case upMirrored = 2
    case down = 3
    case downMirrored = 4
    case leftMirrored = 5
    case right = 6
    case rightMirrored = 7
    case left = 8

    /// Whether displaying the image rotates it a quarter turn, swapping its
    /// width and height.
    public var swapsDimensions: Bool { rawValue >= 5 }

    /// The orientation for a native tag value, or `nil` outside 1...8.
    init?(nativeValue: Int) {
        self.init(rawValue: nativeValue)
    }
}

/// How a source's stored pixels are laid out and interpreted.
public struct PixelMetadata: Sendable, Equatable {
    /// Bands (channels) per pixel, including alpha.
    public var channels: Int

    /// Whether one of the channels is alpha.
    public var hasAlpha: Bool

    /// How the channel values are interpreted. This is not colour management:
    /// it does not say whether an embedded ICC profile was applied.
    public var interpretation: PixelInterpretation

    /// The numeric type of each sample.
    public var sampleFormat: PixelSampleFormat

    /// Bits per sample as stored by the source (for example 1 for a bilevel
    /// PNG, 16 for a 16-bit one), when known.
    public var bitsPerSample: Int?

    /// Whether the source is palette-based, when the loader reports it
    /// reliably (PNG); `nil` otherwise.
    public var isPalette: Bool?

    public init(
        channels: Int,
        hasAlpha: Bool,
        interpretation: PixelInterpretation,
        sampleFormat: PixelSampleFormat,
        bitsPerSample: Int? = nil,
        isPalette: Bool? = nil
    ) {
        self.channels = channels
        self.hasAlpha = hasAlpha
        self.interpretation = interpretation
        self.sampleFormat = sampleFormat
        self.bitsPerSample = bitsPerSample
        self.isPalette = isPalette
    }
}

/// How channel values are interpreted. Treat unrecognised values as
/// ``unknown``: libvips can add interpretations that Hokusai does not model yet.
public enum PixelInterpretation: Sendable, Equatable {
    case grayscale
    case sRGB
    /// RGB without the sRGB transfer curve, including 16-bit RGB.
    case rgb
    case cmyk
    case lab
    case lch
    case xyz
    case hsv
    case scRGB
    case multiband
    case unknown
}

/// The numeric type of each sample. Treat unrecognised values as ``unknown``.
public enum PixelSampleFormat: Sendable, Equatable {
    case uint8
    case int8
    case uint16
    case int16
    case uint32
    case int32
    case float32
    case float64
    case complex
    case unknown
}

/// The unit a source preferred for its resolution.
public enum ResolutionUnit: Sendable, Equatable {
    case inch
    case centimetre
}

/// Page and document facts for multi-page sources.
public struct PageMetadata: Sendable, Equatable {
    /// The number of pages or frames in the source; 1 for single-page formats.
    public var count: Int

    /// The height of each page in a multi-page source, when reported.
    public var height: Int?

    /// The index of the primary image in a HEIF container, when reported.
    public var primary: Int?

    /// The number of TIFF sub-images (subIFDs, for example a pyramid), when reported.
    public var subIFDCount: Int?

    public init(count: Int = 1, height: Int? = nil, primary: Int? = nil, subIFDCount: Int? = nil) {
        self.count = count
        self.height = height
        self.primary = primary
        self.subIFDCount = subIFDCount
    }
}

/// Animation facts, present only for sources that are actually animated.
public struct AnimationMetadata: Sendable, Equatable {
    /// How many times the animation plays; 0 means it loops forever.
    public var loopCount: Int

    /// The display time of each frame. A frame with no recorded delay is zero.
    public var frameDelays: [Duration]

    public init(loopCount: Int, frameDelays: [Duration]) {
        self.loopCount = loopCount
        self.frameDelays = frameDelays
    }
}

/// Image pixel density expressed in dots per inch.
public struct ImageDensity: Sendable, Equatable {
    /// Horizontal resolution in dots per inch.
    public let horizontal: Double
    /// Vertical resolution in dots per inch.
    public let vertical: Double

    /// Creates an anisotropic pixel-density value.
    public init(horizontal: Double, vertical: Double) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
}

extension ImageMetadata: CustomStringConvertible {
    public var description: String {
        var parts = ["\(width)x\(height)"]
        if let format { parts.append(format.rawValue.uppercased()) }
        parts.append("\(pixel.channels) channels")
        if pixel.hasAlpha { parts.append("alpha") }
        parts.append("\(pixel.interpretation)")
        if pages.count > 1 { parts.append(isAnimated ? "\(pages.count) frames" : "\(pages.count) pages") }
        return parts.joined(separator: ", ")
    }
}
