import Foundation

/// The physical size of a PDF page, in PostScript points (1/72 inch).
///
/// A page size says how big the page is. Fixed paper sizes carry no
/// resolution: the embedded raster's effective DPI follows from its pixel
/// size and the area it is placed in (see ``PDFOptions/maxEffectiveDPI``).
public enum PDFPageSize: Sendable, Equatable {
    /// A page sized from the raster: its pixel dimensions at `dpi`, plus any
    /// margins. `dpi` must be finite and greater than zero.
    case image(dpi: Double = 72)

    /// ISO A4, 595.276 × 841.89 points.
    case a4(PDFPageOrientation = .portrait)

    /// US Letter, 612 × 792 points.
    case letter(PDFPageOrientation = .portrait)

    /// An exact page size in points.
    case points(width: Double, height: Double)
}

/// Orientation of a fixed paper size.
public enum PDFPageOrientation: Sendable, Equatable {
    case portrait
    case landscape
}

/// Space kept free around the placed raster, in points.
public struct PDFMargins: Sendable, Equatable {
    public var top: Double
    public var leading: Double
    public var bottom: Double
    public var trailing: Double

    public init(top: Double = 0, leading: Double = 0, bottom: Double = 0, trailing: Double = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    /// The same margin on every side.
    public static func all(_ value: Double) -> PDFMargins {
        PDFMargins(top: value, leading: value, bottom: value, trailing: value)
    }

    /// No margins.
    public static let none = PDFMargins()
}

/// Optional document properties written to the PDF information dictionary.
///
/// Nothing is copied from the source image's EXIF, XMP, or IPTC; only what is
/// set here is written.
public struct PDFDocumentMetadata: Sendable, Equatable {
    public var title: String?
    public var author: String?
    public var subject: String?
    public var keywords: String?
    public var creator: String?

    /// The creation date to record. When `nil`, Cairo records the current
    /// time; set it for reproducible output.
    public var creationDate: Date?

    /// The modification date to record. Not written when `nil`.
    public var modificationDate: Date?

    public init(
        title: String? = nil, author: String? = nil, subject: String? = nil, keywords: String? = nil,
        creator: String? = nil, creationDate: Date? = nil, modificationDate: Date? = nil
    ) {
        self.title = title
        self.author = author
        self.subject = subject
        self.keywords = keywords
        self.creator = creator
        self.creationDate = creationDate
        self.modificationDate = modificationDate
    }
}

/// How a pipeline is exported as a raster PDF.
///
/// `.pdf()` is a raster-document terminal: the evaluated pixels are embedded as
/// an image on a page. Text drawn into the pipeline has already become pixels,
/// so it is not selectable, and an input PDF that is rasterised and written
/// again loses its vector content, links, and structure. Vector documents are
/// a separate surface.
public struct PDFOptions: Sendable, Equatable {
    /// The page size. Defaults to a page that fits the raster at 72 DPI.
    public var pageSize: PDFPageSize

    /// Space kept free around the raster.
    public var margins: PDFMargins

    /// Where the aspect-fitted raster sits within the margins. Centred by default.
    public var anchor: CanvasAnchor

    /// A colour that fills the page behind the raster. `nil` leaves the page
    /// unpainted, and transparent pixels stay transparent in the PDF; use
    /// `.white` for print-oriented output.
    public var background: Color?

    /// When set, a raster whose effective resolution on the page exceeds this
    /// many DPI is downsampled (Lanczos) to it before embedding. Off by
    /// default: Hokusai never resamples because a page has a physical size.
    public var maxEffectiveDPI: Double?

    /// Document properties; none are written by default.
    public var metadata: PDFDocumentMetadata?

    public init(
        pageSize: PDFPageSize = .image(),
        margins: PDFMargins = .none,
        anchor: CanvasAnchor = .center,
        background: Color? = nil,
        maxEffectiveDPI: Double? = nil,
        metadata: PDFDocumentMetadata? = nil
    ) {
        self.pageSize = pageSize
        self.margins = margins
        self.anchor = anchor
        self.background = background
        self.maxEffectiveDPI = maxEffectiveDPI
        self.metadata = metadata
    }
}

/// Page facts for a PDF output.
public struct PDFOutputDetails: Sendable, Equatable {
    /// The number of pages written.
    public let pageCount: Int

    /// The width of the first page, in points.
    public let pageWidth: Double

    /// The height of the first page, in points.
    public let pageHeight: Double
}
