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
/// - `pixel.png` — 1×1 RGBA pixel.
/// - `landscape-asym.jpg` — 320×200 JPEG, flat black background with a
///   high-detail noise block near the left edge (x 10..110, y 50..150), so
///   content-aware crops are distinguishable from centre crops.
/// - `portrait-asym.jpg` — 200×320 JPEG, noise block near the top.
/// - `orientation-6.jpg` — 120×80 JPEG carrying EXIF Orientation=6; displays
///   as 80×120 after auto-rotation.

func fixtureURL(named name: String, ext: String) throws -> URL {
    guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures") else {
        throw HokusaiError.fileNotFound("Fixture \(name).\(ext) not found")
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
    var isInvalidDimensions: Bool {
        if case .invalidDimensions = self { return true }
        return false
    }

    var isFileNotFound: Bool {
        if case .fileNotFound = self { return true }
        return false
    }

    var isInvalidImageData: Bool {
        if case .invalidImageData = self { return true }
        return false
    }

    var isLoadFailed: Bool {
        if case .loadFailed = self { return true }
        return false
    }
}
