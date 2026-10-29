import Foundation
import Hokusai
import Testing

/// Committed fixtures shared with the internal suite through a symlink, so
/// layer A reads the same files without duplicating binaries.
func fixtureURL(named name: String, ext: String) throws -> URL {
    guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures") else {
        throw HokusaiError.io(url: URL(fileURLWithPath: "\(name).\(ext)"), operation: .read, reason: "fixture not found")
    }
    return url
}

func fixtureData(named name: String, ext: String) throws -> Data {
    try Data(contentsOf: fixtureURL(named: name, ext: ext))
}
