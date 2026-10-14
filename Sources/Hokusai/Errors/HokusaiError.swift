import Foundation

/// Hokusai's image-processing failures.
///
/// Branch on the case, not on message text. Each case is chosen where the
/// failure happened (source, transform, encoder, sink, scheduler, runtime),
/// never by parsing native diagnostics. Cancellation is not a case: async
/// terminals throw Swift's `CancellationError`.
public enum HokusaiError: Error, Sendable {
    /// Caller-supplied source shape is invalid before any decoding, such as
    /// empty data or a non-file URL.
    case invalidInput(reason: String)

    /// A public option or configuration value is invalid.
    case invalidOption(name: String, reason: String)

    /// The request is valid but unavailable with this build or runtime.
    case unsupported(feature: String, reason: String?)

    /// A source could not be opened or decoded after validation.
    case decode(FailureContext)

    /// An image operation failed after its options were validated.
    case transform(FailureContext)

    /// An available encoder failed to produce output.
    case encode(FailureContext)

    /// A known filesystem read or write failed.
    case io(url: URL, operation: FileOperation, reason: String)

    /// A configured safety or admission limit rejected the work.
    case resource(ResourceFailure)

    /// libvips initialization or an internal Hokusai invariant failed.
    case runtime(FailureContext)
}

/// Where a failure happened and why.
public struct FailureContext: Sendable, Equatable {
    /// Human-readable operation label such as `resize` or
    /// `composite layer 2 / decode input data`. Not a stable identifier.
    public let operation: String

    /// Hokusai's explanation of the failure.
    public let reason: String

    /// Best-effort native diagnostic text. libvips keeps one error log for the
    /// whole process, so under concurrent failures this may include messages
    /// from other evaluations, or be absent.
    public let diagnostic: String?

    public init(operation: String, reason: String, diagnostic: String? = nil) {
        self.operation = operation
        self.reason = reason
        self.diagnostic = diagnostic
    }
}

/// A limit that rejected work. See ``HokusaiError/resource(_:)``.
public struct ResourceFailure: Sendable, Equatable {
    public let kind: ResourceKind
    /// The configured limit, when there is one.
    public let limit: Int?
    /// The observed value, when known.
    public let actual: Int?
    public let reason: String

    public init(kind: ResourceKind, limit: Int?, actual: Int?, reason: String) {
        self.kind = kind
        self.limit = limit
        self.actual = actual
        self.reason = reason
    }
}

/// The kind of limit in a ``ResourceFailure``.
///
/// A struct rather than an enum so new kinds can be added without breaking
/// exhaustive switches.
public struct ResourceKind: Sendable, Hashable, CustomStringConvertible {
    public let name: String

    /// `RuntimeConfiguration.maxQueuedEvaluations` was reached.
    public static let queuedEvaluations = ResourceKind(name: "queuedEvaluations")

    /// `InputLimits.maxBytes`: the encoded source is too large.
    public static let encodedBytes = ResourceKind(name: "encodedBytes")

    /// `InputLimits.maxPixels`: the decoded image has too many pixels.
    public static let decodedPixels = ResourceKind(name: "decodedPixels")

    /// `InputLimits.maxChannels`: the decoded image has too many bands.
    public static let channels = ResourceKind(name: "channels")

    public var description: String { name }
}

/// The filesystem action in an ``HokusaiError/io(url:operation:reason:)`` error.
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
        case .unsupported(let feature, let reason):
            return "Unsupported: \(feature)" + (reason.map { " (\($0))" } ?? "")
        case .decode(let context):
            return "Could not decode image during \(context.operation): \(context.reason)"
        case .transform(let context):
            return "Could not transform image during \(context.operation): \(context.reason)"
        case .encode(let context):
            return "Could not encode image during \(context.operation): \(context.reason)"
        case .io(let url, let operation, let reason):
            return "Could not \(operation.rawValue) \(url.path): \(reason)"
        case .resource(let failure):
            return "Resource limit reached (\(failure.kind)): \(failure.reason)"
        case .runtime(let context):
            return "Hokusai runtime failure during \(context.operation): \(context.reason)"
        }
    }
}

// MARK: - Internal construction

extension FailureContext {
    /// Context for a failed native call, with a best-effort libvips diagnostic.
    static func native(_ operation: String, _ reason: String) -> FailureContext {
        FailureContext(operation: operation, reason: reason, diagnostic: VipsDiagnostics.drain())
    }

    /// The same context labelled as happening inside `scope`.
    func scoped(_ scope: String) -> FailureContext {
        FailureContext(operation: "\(scope) / \(operation)", reason: reason, diagnostic: diagnostic)
    }
}

extension HokusaiError {
    /// A native image operation failed.
    static func nativeTransform(_ operation: String) -> HokusaiError {
        .transform(.native(operation, "libvips could not complete \(operation)"))
    }

    /// A native encoder failed.
    static func nativeEncode(_ format: String) -> HokusaiError {
        .encode(.native("encode \(format)", "libvips could not encode \(format)"))
    }

    /// Native memory for an operation argument could not be allocated.
    static func allocationFailed(_ operation: String) -> HokusaiError {
        .runtime(FailureContext(operation: operation, reason: "could not allocate a native argument"))
    }

    /// Labels a failure as happening inside `scope`, such as a composite layer.
    func scoped(_ scope: String) -> HokusaiError {
        switch self {
        case .decode(let context): .decode(context.scoped(scope))
        case .transform(let context): .transform(context.scoped(scope))
        case .encode(let context): .encode(context.scoped(scope))
        case .runtime(let context): .runtime(context.scoped(scope))
        default: self
        }
    }
}
