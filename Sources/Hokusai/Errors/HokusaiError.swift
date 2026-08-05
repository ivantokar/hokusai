import Foundation

/// PURPOSE: Comprehensive error enum for all Hokusai operations
/// A stable, Swift-facing description of an image-processing failure.
///
/// The cases that name libvips directly remain deprecated compatibility cases.
/// New pipeline APIs use the typed input, option, decode, transform, encode,
/// I/O, cancellation, and runtime categories below.
public enum HokusaiError: Error, Sendable {
    case invalidInput(String)
    case invalidOption(name: String, reason: String)
    case unsupported(feature: String)
    case decode(FailureContext)
    case transform(FailureContext)
    case encode(FailureContext)
    case io(url: URL, operation: FileOperation, reason: String)
    case cancelled
    case runtime(FailureContext)

    // MARK: Legacy compatibility

    case initializationFailed(String)
    case loadFailed(String)
    case saveFailed(String)
    case invalidOperation(String)
    case invalidDimensions(String)
    case unsupportedFormat(String)
    case conversionFailed(String)  // Backend conversion errors
    case textRenderingFailed(String)
    case vipsError(String)
    @available(*, deprecated, message: "ImageMagick backend was removed.")
    case magickError(String)
    case memoryAllocationFailed
    case fileNotFound(String)
    case invalidImageData
    case notSupported(String)
}

/// Context retained for a stable public error while keeping native details
/// behind Hokusai's adapter boundary.
public struct FailureContext: Sendable, Equatable {
    public let operation: String
    public let message: String

    public init(operation: String, message: String) {
        self.operation = operation
        self.message = message
    }
}

public enum FileOperation: String, Sendable {
    case read
    case write
}

extension HokusaiError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidInput(let reason):
            return "Invalid image input: \(reason)"
        case .invalidOption(let name, let reason):
            return "Invalid option '\(name)': \(reason)"
        case .unsupported(let feature):
            return "Unsupported feature: \(feature)"
        case .decode(let context):
            return "Could not decode image during \(context.operation): \(context.message)"
        case .transform(let context):
            return "Could not transform image during \(context.operation): \(context.message)"
        case .encode(let context):
            return "Could not encode image during \(context.operation): \(context.message)"
        case .io(let url, let operation, let reason):
            return "Could not \(operation.rawValue) \(url.path): \(reason)"
        case .cancelled:
            return "Image processing was cancelled"
        case .runtime(let context):
            return "Hokusai runtime failure during \(context.operation): \(context.message)"
        case .initializationFailed(let message):
            return "Failed to initialize Hokusai: \(message)"
        case .loadFailed(let message):
            return "Failed to load image: \(message)"
        case .saveFailed(let message):
            return "Failed to save image: \(message)"
        case .invalidOperation(let message):
            return "Invalid operation: \(message)"
        case .invalidDimensions(let message):
            return "Invalid dimensions: \(message)"
        case .unsupportedFormat(let format):
            return "Unsupported image format: \(format)"
        case .conversionFailed(let message):
            return "Backend conversion failed: \(message)"
        case .textRenderingFailed(let message):
            return "Text rendering failed: \(message)"
        case .vipsError(let message):
            return "libvips error: \(message)"
        case .magickError(let message):
            return "Legacy ImageMagick error (compatibility only): \(message)"
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
