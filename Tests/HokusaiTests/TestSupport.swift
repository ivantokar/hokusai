import Foundation
import Testing
@testable import Hokusai

/// Shared fixture helpers for the Hokusai test suite.
///
/// The suite uses swift-testing (not XCTest): swift-corelibs-xctest has a
/// known unresolved RunLoop deadlock on Linux when a target contains many
/// test methods (swiftlang/swift-corelibs-xctest#504), which hangs `swift
/// test` at a nondeterministic position. swift-testing does not use the
/// RunLoop-based waiter and runs reliably on both platforms.
///
/// `Hokusai.initialize()` is idempotent and thread-safe, so tests call it
/// directly — no test-side actor or serialization is needed. Tests run in
/// parallel by default, which doubles as a standing concurrency check on the
/// library's thread-safety policy.
///
/// Fixture inventory:
/// - `pixel.png` — 1×1 grey+alpha pixel with valid chunk checksums.
/// - `corrupt-crc.png` — `pixel.png` with a wrong IDAT checksum: loads under
///   `DecodeFailureLevel.none`/`.truncated`, fails under `.error`/`.warning`.
/// - `truncated.jpg` — first 60% of `landscape-asym.jpg`: loads only under
///   `DecodeFailureLevel.none`.
/// - `multipage.tif` — three 16×16 grey RGB pages with levels 30, 120, 210.
/// - `landscape-asym.jpg` — 320×200 JPEG, flat black background with a
///   high-detail noise block near the left edge (x 10..110, y 50..150), so
///   content-aware crops are distinguishable from centre crops.
/// - `portrait-asym.jpg` — 200×320 JPEG, noise block near the top.
/// - `orientation-6.jpg` — 120×80 JPEG carrying EXIF Orientation=6; displays
///   as 80×120 after auto-rotation.

func fixtureURL(named name: String, ext: String) throws -> URL {
    guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures") else {
        throw HokusaiError.io(url: URL(fileURLWithPath: "\(name).\(ext)"), operation: .read, reason: "fixture not found")
    }
    return url
}

func fixturePath(named name: String, ext: String) throws -> String {
    try fixtureURL(named: name, ext: ext).path
}

func loadFixtureData(named name: String, ext: String) throws -> Data {
    try Data(contentsOf: fixtureURL(named: name, ext: ext))
}

/// Expects that `body` throws a `HokusaiError` matched by `matcher`.
func expectHokusaiError<T>(
    _ body: () throws -> T,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ matcher: (HokusaiError) -> Bool
) {
    do {
        _ = try body()
        Issue.record("expected a HokusaiError, but no error was thrown", sourceLocation: sourceLocation)
    } catch let error as HokusaiError {
        #expect(matcher(error), "unexpected error: \(error)", sourceLocation: sourceLocation)
    } catch {
        Issue.record("expected HokusaiError, got \(error)", sourceLocation: sourceLocation)
    }
}

extension HokusaiError {
    var isInvalidOption: Bool {
        if case .invalidOption = self { return true }
        return false
    }

    var isInvalidInput: Bool {
        if case .invalidInput = self { return true }
        return false
    }

    var isReadFailure: Bool {
        if case .io(_, .read, _) = self { return true }
        return false
    }

    var isDecode: Bool {
        if case .decode = self { return true }
        return false
    }
}
