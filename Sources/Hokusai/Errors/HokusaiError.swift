import Foundation

/// A stable Swift-facing description of an image-processing failure.
///
/// The cases that name libvips directly remain deprecated compatibility cases.
/// New pipeline APIs use the typed input, option, decode, transform, encode,
/// I/O, and runtime categories below. Cancellation is reported as Swift's
/// standard `CancellationError`.
public enum HokusaiError: Error, Sendable {
    case invalidInput(String)
    case invalidOption(name: String, reason: String)
    case unsupported(feature: String)
    case decode(FailureContext)
    case transform(FailureContext)
    case encode(FailureContext)
    case io(url: URL, operation: FileOperation, reason: String)
    case runtime(FailureContext)
    /// The evaluation queue is full (`RuntimeConfiguration.maxQueuedEvaluations`).
    case overloaded(FailureContext)

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

/// Context retained by typed errors while native details stay behind Hokusai's
/// adapter boundary.
public struct FailureContext: Sendable, Equatable {
    public let operation: String
    public let message: String

    /// Creates context that identifies the failed operation and its explanation.
    public init(operation: String, message: String) {
        self.operation = operation
        self.message = message
    }
}

/// The filesystem action associated with an ``HokusaiError/io(url:operation:reason:)`` error.
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
        case .runtime(let context):
            return "Hokusai runtime failure during \(context.operation): \(context.message)"
        case .overloaded(let context):
            return "Hokusai is overloaded during \(context.operation): \(context.message)"
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

/// Which stage of pipeline evaluation produced an untyped failure.
enum PipelineFailureCategory { case decode, transform, encode }

extension HokusaiError {
    /// Maps an evaluation failure to the stable pipeline error vocabulary.
    ///
    /// Already-typed pipeline errors pass through unchanged; legacy and native
    /// errors are wrapped with the failing operation and stage.
    static func pipeline(_ error: Error, operation: String, category: PipelineFailureCategory) -> HokusaiError {
        if let error = error as? HokusaiError {
            switch error {
            case .invalidInput, .invalidOption, .unsupported, .decode, .transform, .encode, .io, .runtime, .overloaded:
                return error
            case .fileNotFound(let path): return .io(url: URL(fileURLWithPath: path), operation: .read, reason: "file not found")
            case .invalidImageData: return .invalidInput("encoded data is empty or invalid")
            default: break
            }
        }
        let context = FailureContext(operation: operation, message: error.localizedDescription)
        switch category {
        case .decode: return .decode(context)
        case .transform: return .transform(context)
        case .encode: return .encode(context)
        }
    }
}
