import Foundation
import XCTest
@testable import Hokusai

/// Shared fixture helpers for the Hokusai test suite.
///
/// `Hokusai.initialize()` is idempotent and thread-safe, so tests call it
/// directly — no test-side actor or serialization is needed.
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

/// Asserts that `expression` throws a `HokusaiError` matched by `matcher`.
func XCTAssertThrowsHokusaiError<T>(
    _ expression: @autoclosure () throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ matcher: (HokusaiError) -> Bool
) {
    XCTAssertThrowsError(try expression(), file: file, line: line) { error in
        guard let hokusaiError = error as? HokusaiError else {
            XCTFail("Expected HokusaiError, got \(error)", file: file, line: line)
            return
        }
        XCTAssertTrue(matcher(hokusaiError), "Unexpected error: \(hokusaiError)", file: file, line: line)
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
