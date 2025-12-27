import Foundation

/// Comprehensive error enum for all Hokusai operations
public enum HokusaiError: Error {
    case initializationFailed(String)
    case loadFailed(String)
    case saveFailed(String)
    case invalidOperation(String)
    case unsupportedFormat(String)
    case conversionFailed(String)  // Backend conversion errors
    case textRenderingFailed(String)
    case vipsError(String)
    case magickError(String)
    case memoryAllocationFailed
    case fileNotFound(String)
    case invalidImageData
    case notSupported(String)
}

extension HokusaiError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .initializationFailed(let message):
            return "Failed to initialize Hokusai: \(message)"
        case .loadFailed(let message):
            return "Failed to load image: \(message)"
        case .saveFailed(let message):
            return "Failed to save image: \(message)"
        case .invalidOperation(let message):
            return "Invalid operation: \(message)"
        case .unsupportedFormat(let format):
            return "Unsupported image format: \(format)"
        case .conversionFailed(let message):
            return "Backend conversion failed: \(message)"
        case .textRenderingFailed(let message):
            return "Text rendering failed: \(message)"
        case .vipsError(let message):
            return "libvips error: \(message)"
        case .magickError(let message):
            return "ImageMagick error: \(message)"
        case .memoryAllocationFailed:
            return "Memory allocation failed"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .invalidImageData:
            return "Invalid image data"
        case .notSupported(let feature):
            return "Feature not supported: \(feature)"
        }
    }
}
