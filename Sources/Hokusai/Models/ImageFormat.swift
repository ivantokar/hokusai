import Foundation

/// Supported image formats
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

    /// File extension for the format
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

    /// MIME type for the format
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

    /// Detect format from file extension
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
