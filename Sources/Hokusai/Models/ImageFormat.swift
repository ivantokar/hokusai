import Foundation

/// Image formats recognized by Hokusai's loaders and legacy encoders.
///
/// Availability is runtime-dependent for some formats because it follows the
/// linked libvips build. The 1.0 pipeline currently exposes a smaller typed
/// output subset; see ``OutputFormat``.
public enum ImageFormat: String, CaseIterable, Sendable {
    case jpeg = "jpeg"
    case png = "png"
    case webp = "webp"
    case gif = "gif"
    case tiff = "tiff"
    case avif = "avif"
    case heif = "heif"
    case pdf = "pdf"
    case svg = "svg"

    /// The preferred filename extension without a leading dot.
    public var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .webp: return "webp"
        case .gif: return "gif"
        case .tiff: return "tiff"
        case .avif: return "avif"
        case .heif: return "heif"
        case .pdf: return "pdf"
        case .svg: return "svg"
        }
    }

    /// The conventional MIME type for the format.
    public var mimeType: String {
        switch self {
        case .jpeg: return "image/jpeg"
        case .png: return "image/png"
        case .webp: return "image/webp"
        case .gif: return "image/gif"
        case .tiff: return "image/tiff"
        case .avif: return "image/avif"
        case .heif: return "image/heif"
        case .pdf: return "application/pdf"
        case .svg: return "image/svg+xml"
        }
    }

    /// Returns the recognized format for a filename extension.
    ///
    /// Both `.jpg` and `.jpeg`, as well as `.heic` and `.heif`, map to their
    /// shared format cases. Unknown extensions return `nil` rather than guessing.
    public static func from(fileExtension: String) -> ImageFormat? {
        let ext = fileExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        switch ext {
        case "jpg", "jpeg": return .jpeg
        case "png": return .png
        case "webp": return .webp
        case "gif": return .gif
        case "tif", "tiff": return .tiff
        case "avif": return .avif
        case "heif", "heic": return .heif
        case "pdf": return .pdf
        case "svg": return .svg
        default: return nil
        }
    }
}
