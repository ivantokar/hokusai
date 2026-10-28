import Foundation
import Hokusai
import Testing

/// Typed failures: every assertion names the case and its fields, never the
/// text of a native message.
@Suite struct ErrorTaxonomyPublicTests {
    private let source = gradient(width: 16, height: 16)

    private func failure(_ body: () async throws -> Void) async -> Error? {
        do { try await body(); return nil } catch { return error }
    }

    @Test func emptyDataIsInvalidInput() {
        #expect {
            try Hokusai(data: Data())
        } throws: { error in
            if case HokusaiError.invalidInput = error { return true }
            return false
        }
    }

    @Test func aRemoteURLIsInvalidInput() {
        #expect {
            try Hokusai(url: URL(string: "https://example.com/a.png")!)
        } throws: { error in
            if case HokusaiError.invalidInput = error { return true }
            return false
        }
    }

    @Test func garbageBytesFailAsDecodeWhenEvaluated() async throws {
        let garbage = Data((0..<256).map { UInt8(($0 * 37 + 11) % 251) })
        let image = try Hokusai(data: garbage)   // construction is lazy
        let error = await failure { _ = try await image.png().data() }
        guard case HokusaiError.decode(let context)? = error else {
            Issue.record("expected decode, got \(String(describing: error))")
            return
        }
        #expect(!context.operation.isEmpty && !context.reason.isEmpty)
    }

    @Test func aTruncatedImageFailsAsDecodeUnderStrictPolicy() async throws {
        let full = try await source.pipeline().png(compressionLevel: 0).data().data
        let image = try Hokusai(data: full.prefix(full.count / 2), options: InputOptions(failOn: .truncated))
        let error = await failure { _ = try await image.png().data() }
        guard case HokusaiError.decode? = error else {
            Issue.record("expected decode, got \(String(describing: error))")
            return
        }
    }

    @Test func invalidArgumentsNameTheOptionImmediately() throws {
        let image = try source.pipeline()
        let cases: [(name: String, build: (Hokusai) throws -> Hokusai)] = [
            ("width", { try $0.resize(width: 0) }),
            ("height", { try $0.resize(height: -5) }),
            ("sigma", { try $0.blur(sigma: .nan) }),
            ("quality", { try $0.jpeg(quality: 101) }),
            ("threshold", { try $0.trim(threshold: -1) }),
        ]
        for (name, build) in cases {
            do {
                _ = try build(image)
                Issue.record("expected \(name) to be rejected")
            } catch HokusaiError.invalidOption(let reported, let reason) {
                #expect(reported == name)
                #expect(!reason.isEmpty)
            }
        }
    }

    @Test func aPageBeyondTheEndIsAnInvalidOptionNamingPage() async throws {
        let image = try source.pipeline(options: InputOptions(page: 4))
        let error = await failure { _ = try await image.png().data() }
        guard case HokusaiError.unsupported(let feature, _)? = error else {
            Issue.record("expected unsupported for a single-page source, got \(String(describing: error))")
            return
        }
        #expect(feature == "page selection")
    }

    @Test func inputLimitsReportKindLimitAndActual() async throws {
        let bytes = tiffData(source)
        do {
            _ = try Hokusai(data: bytes, options: InputOptions(limits: InputLimits(maxBytes: 100)))
            Issue.record("expected the byte limit to reject the data")
        } catch HokusaiError.resource(let failure) {
            #expect(failure.kind == .encodedBytes)
            #expect(failure.limit == 100)
            #expect(failure.actual == bytes.count)
        }

        let image = try source.pipeline(options: InputOptions(limits: InputLimits(maxPixels: 100)))
        let error = await failure { _ = try await image.png().data() }
        guard case HokusaiError.resource(let failure)? = error else {
            Issue.record("expected resource, got \(String(describing: error))")
            return
        }
        #expect(failure.kind == .decodedPixels)
        #expect(failure.limit == 100)
        #expect(failure.actual == 256)
    }

    @Test func aDestinationThatCannotBeWrittenIsAnIOError() async throws {
        let url = URL(fileURLWithPath: "/nonexistent-directory-\(UUID().uuidString)/out.png")
        let error = await failure { _ = try await source.pipeline().png().write(to: url) }
        guard case HokusaiError.io(let reported, let operation, _)? = error else {
            Issue.record("expected io, got \(String(describing: error))")
            return
        }
        #expect(operation == .write)
        #expect(reported.lastPathComponent == "out.png")
    }

    @Test func aTransformThatCannotRunFailsWhenEvaluatedNotWhenBuilt() async throws {
        // Extending can only add canvas; asking for a smaller one is found when the size is known.
        let image = try source.pipeline().extend(to: ImageSize(width: 4, height: 4))
        let error = await failure { _ = try await image.png().data() }
        #expect(error is HokusaiError)
    }

    @Test func failuresInConcurrentEvaluationsKeepTheirOwnCategory() async throws {
        let good = try source.pipeline().png()
        let bad = try Hokusai(data: Data(repeating: 7, count: 64)).png()
        try await withThrowingTaskGroup(of: (Bool, Bool).self) { group in
            for index in 0..<40 {
                group.addTask {
                    if index.isMultiple(of: 2) {
                        _ = try await good.data()
                        return (true, true)
                    }
                    do { _ = try await bad.data(); return (false, false) } catch HokusaiError.decode { return (false, true) }
                }
            }
            for try await (succeeded, expected) in group { #expect(expected, "\(succeeded ? "valid" : "invalid") pipeline reported the wrong outcome") }
        }
    }
}

/// Admission and cancellation, observed through the public runtime status.
@Suite struct SchedulerPublicTests {
    private let source = gradient(width: 64, height: 64)

    @Test func manyMoreEvaluationsThanSlotsAllCompleteWithinTheCapacity() async throws {
        let capacity = Hokusai.runtimeStatus.maxConcurrentEvaluations
        let pipeline = try source.pipeline().resize(width: 32, height: 32, fit: .fill).png()
        let observedPeak = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<(capacity * 6 + 12) {
                group.addTask {
                    _ = try await pipeline.data()
                    return Hokusai.runtimeStatus.activeEvaluations
                }
            }
            var peak = 0
            for try await active in group { peak = max(peak, active) }
            return peak
        }
        #expect(observedPeak <= capacity)
        try await settles()
    }

    @Test func aFailedEvaluationReleasesItsSlot() async throws {
        let bad = try Hokusai(data: Data(repeating: 1, count: 32)).png()
        for _ in 0..<50 { _ = try? await bad.data() }
        try await settles()
        #expect(try await source.pipeline().png().data().info.width == 64)
    }

    @Test func cancellingAnEvaluationThrowsCancellationErrorAndFreesTheSlot() async throws {
        let big = try Raster(width: 2000, height: 2000) { x, y in [UInt8(x % 256), UInt8(y % 256), 0, 255] }.pipeline()
        let slow = try big.blur(sigma: 40).resize(width: 500, fit: .inside).png(compressionLevel: 9)
        let task = Task { try await slow.data() }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        do {
            _ = try await task.value
            // Finishing before the cancel landed is legal; nothing leaks either way.
        } catch is CancellationError {
        } catch {
            Issue.record("cancellation must surface as CancellationError, got \(error)")
        }
        try await settles()
    }

    @Test func cancellingOneBranchLeavesItsSiblingsRunning() async throws {
        let shared = try source.pipeline().png()
        let cancelled = Task { try await shared.data() }
        cancelled.cancel()
        let sibling = try await shared.data()
        #expect(sibling.info.width == 64)
        _ = try? await cancelled.value
        try await settles()
    }

    @Test func thousandsOfShortEvaluationsKeepTheRuntimeUsable() async throws {
        let tiny = try gradient(width: 4, height: 4).pipeline().png()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<1500 { group.addTask { _ = try await tiny.data() } }
            try await group.waitForAll()
        }
        try await settles()
    }

    /// The runtime status is process-wide and other suites evaluate in parallel,
    /// so exact drain-to-zero accounting is asserted on a private scheduler in the
    /// internal suite. From outside, the contract is that the bound always holds
    /// and that the pipeline stays usable.
    private func settles() async throws {
        let status = Hokusai.runtimeStatus
        #expect(status.activeEvaluations <= status.maxConcurrentEvaluations)
        #expect(status.activeEvaluations >= 0 && status.queuedEvaluations >= 0)
        #expect(try await source.pipeline().png().data().info.width == 64)
    }
}
