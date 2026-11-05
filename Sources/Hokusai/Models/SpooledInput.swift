import Foundation

/// A temporary file that holds an upload and is removed when nothing can read it any more.
///
/// A pipeline is a value that can be copied, branched and evaluated many times, and it is
/// evaluated later than it is built, so no single call site knows when the file is finished
/// with. The plan holds this object instead, and the file goes with the last plan that
/// refers to it: after the final copy of the pipeline (and any evaluation still running on
/// it) is released. An open file stays readable after it is unlinked, so a decode that has
/// begun is never cut short.
final class SpooledFile: Sendable {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    deinit {
        unlink(url.path)
    }
}

extension Hokusai {
    /// Creates a pipeline from an upload that arrives in chunks, without holding a large one in memory.
    ///
    /// The chunks are kept in memory while the upload is small. When it grows past
    /// `memoryLimit` bytes the bytes so far are moved to a temporary file and the rest is
    /// appended to it as it arrives, so the encoded upload never occupies more than
    /// `memoryLimit` plus one chunk of memory, however large it is. libvips then reads the
    /// image from the file with random access, which is why a decode does not need the body
    /// as one buffer.
    ///
    /// The upload is bounded while it is read: the first chunk that would take the total over
    /// ``InputLimits/maxBytes`` of `options` stops the read with
    /// ``HokusaiError/resource(_:)``, the rest of the body is never requested, and nothing
    /// is left on disk. The same holds when the sequence throws, when it ends with no bytes
    /// (``HokusaiError/invalidInput(reason:)``) and when the calling task is cancelled
    /// (`CancellationError`). Nothing is decoded here, so a corrupt image is reported by the
    /// terminal method that evaluates the pipeline, as for ``init(data:options:)``.
    ///
    /// A spooled pipeline owns its file. It is removed when the last copy of the pipeline,
    /// and every evaluation running on one, has been released; there is nothing to clean up.
    /// A process that dies first leaves its file behind; files are named `hokusai-upload-`
    /// followed by random characters, are readable by their owner only, and sit in
    /// `spoolDirectory`, so a server can sweep that directory when it starts.
    ///
    /// This bounds the memory of the *encoded* upload. The memory libvips uses to decode and
    /// transform the image is a separate matter (see ``InputOptions/AccessMode`` and
    /// ``InputLimits/maxPixels``). Writing to the file happens on the calling task, one chunk
    /// at a time.
    ///
    /// - Parameters:
    ///   - chunks: The upload, in order. Chunks of any size, including empty ones.
    ///   - options: Input options, including the `maxBytes` bound on the whole upload.
    ///   - memoryLimit: The largest upload kept in memory, in bytes (default 1 MiB). `0`
    ///     spools every upload.
    ///   - spoolDirectory: Where the temporary file goes. Defaults to the system temporary
    ///     directory; it must exist.
    ///
    /// - Throws: ``HokusaiError/invalidInput(reason:)`` for an empty upload,
    ///   ``HokusaiError/resource(_:)`` over the limit,
    ///   ``HokusaiError/invalidOption(name:reason:)`` for a bad option, and
    ///   ``HokusaiError/io(url:operation:reason:)`` when the file cannot be created or written
    ///   (a missing directory, permissions, a full disk). Whatever the sequence throws is
    ///   rethrown unchanged.
    public init<Chunks: AsyncSequence>(
        spooling chunks: Chunks,
        options: InputOptions = .init(),
        memoryLimit: Int = 1_048_576,
        spoolDirectory: URL? = nil
    ) async throws where Chunks.Element == Data {
        try options.validate()
        guard memoryLimit >= 0 else {
            throw HokusaiError.invalidOption(name: "memoryLimit", reason: "must be zero or greater")
        }
        var memory = Data()
        var spool: SpoolWriter?
        var total = 0
        do {
            for try await chunk in chunks {
                try Task.checkCancellation()
                // Checked before the bytes are kept, so an oversized body is refused at the
                // chunk that crosses the limit and the rest is never read.
                let (next, overflow) = total.addingReportingOverflow(chunk.count)
                try options.limits.checkEncodedBytes(overflow ? Int.max : next)
                if chunk.isEmpty { continue }
                total = next
                if let writer = spool {
                    try writer.append(chunk)
                } else if total > memoryLimit {
                    let writer = try SpoolWriter(directory: spoolDirectory ?? FileManager.default.temporaryDirectory)
                    spool = writer
                    try writer.append(memory)
                    try writer.append(chunk)
                    memory = Data()
                } else {
                    memory.append(chunk)
                }
            }
            guard total > 0 else {
                throw HokusaiError.invalidInput(reason: "encoded data is empty")
            }
        } catch {
            spool?.discard()
            throw error
        }
        if let spool {
            let file = try spool.finish()
            self.init(plan: .source(.file(file.url, options, file)))
        } else {
            self.init(plan: .source(.data(memory, options)))
        }
    }
}

/// Appends to a new temporary file and hands it over as a ``SpooledFile`` when finished.
private final class SpoolWriter {
    private var descriptor: Int32
    private let url: URL

    init(directory: URL) throws {
        var template = Array(directory.appendingPathComponent("hokusai-upload-XXXXXX").path.utf8CString)
        let descriptor = mkstemp(&template)
        let path = String(cString: template)
        guard descriptor >= 0 else {
            throw HokusaiError.io(
                url: directory, operation: .write,
                reason: "could not create a temporary file: \(String(cString: strerror(errno)))")
        }
        self.descriptor = descriptor
        self.url = URL(fileURLWithPath: path)
    }

    deinit {
        if descriptor >= 0 { close(descriptor) }
    }

    func append(_ data: Data) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = write(descriptor, bytes.baseAddress! + offset, bytes.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw HokusaiError.io(url: url, operation: .write, reason: String(cString: strerror(errno)))
                }
                offset += written
            }
        }
    }

    /// Closes the file and gives ownership of it to a ``SpooledFile``.
    func finish() throws -> SpooledFile {
        let result = close(descriptor)
        descriptor = -1
        guard result == 0 else {
            unlink(url.path)
            throw HokusaiError.io(url: url, operation: .write, reason: String(cString: strerror(errno)))
        }
        return SpooledFile(url: url)
    }

    /// Closes and removes the file after a failure.
    func discard() {
        if descriptor >= 0 { close(descriptor) }
        descriptor = -1
        unlink(url.path)
    }
}
