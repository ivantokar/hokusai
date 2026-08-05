import Foundation

/// Dedicated bounded queue for terminal libvips evaluation.
///
/// Pipeline construction is synchronous and cheap; encoding and file writes are
/// potentially blocking and must not occupy Swift's cooperative executor.
enum PipelineExecutor {
    private static let queue = DispatchQueue(
        label: "com.ivantokar.hokusai.evaluation",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private static let capacity = DispatchSemaphore(
        value: max(1, ProcessInfo.processInfo.activeProcessorCount)
    )

    static func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                capacity.wait()
                defer { capacity.signal() }
                do {
                    try Task.checkCancellation()
                    continuation.resume(returning: try work())
                } catch is CancellationError {
                    continuation.resume(throwing: HokusaiError.cancelled)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
