import CVips

/// Process-scoped libvips runtime.
///
/// libvips is initialized at most once and stays available for the lifetime of
/// the process. Hokusai never calls `vips_shutdown()`: libvips documents it as
/// optional, and the runtime cannot be initialized again afterwards.
enum VipsRuntime {
    /// Swift lazily evaluates static stored properties exactly once, even under
    /// concurrent first use, so no lock or state machine is needed. A failure is
    /// cached: a process whose libvips failed to start stays unusable.
    private static let initialization: Result<Void, HokusaiError> = {
        guard vips_init("Hokusai") == 0 else {
            return .failure(.initializationFailed(VipsBackend.getLastError()))
        }
        return .success(())
    }()

    /// Ensures libvips has been initialized for this process.
    static func ensureInitialized() throws {
        try initialization.get()
    }
}
