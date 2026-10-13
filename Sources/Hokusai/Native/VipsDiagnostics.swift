import Foundation
import CVips

/// Best-effort access to libvips' process-global error log.
///
/// libvips keeps one textual error buffer for every thread. Draining it after a
/// failure captures useful detail, but the text may include messages from
/// other concurrent evaluations, or have been drained by one of them. It is
/// therefore only ever attached as `FailureContext.diagnostic` and never used
/// to classify an error. Evaluations are not serialized to make it exact.
enum VipsDiagnostics {
    /// Serializes Hokusai's own drains; it cannot isolate native messages.
    private static let lock = NSLock()

    /// Copies and clears the libvips error log; `nil` when empty.
    static func drain() -> String? {
        lock.withLock {
            guard let buffer = swift_vips_error_copy() else { return nil }
            defer { g_free(buffer) }
            let message = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
            return message.isEmpty ? nil : message
        }
    }
}
