import Foundation
import XCTest
@testable import Hokusai

private actor HokusaiTestRuntime {
    static let shared = HokusaiTestRuntime()
    private var isInitialized = false

    func withHokusai<T>(_ work: () async throws -> T) async throws -> T {
        if !isInitialized {
            try Hokusai.initialize()
            isInitialized = true
        }

        return try await work()
    }
}

private func loadFixtureData(named name: String, ext: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures") else {
        throw HokusaiError.fileNotFound("Fixture \(name).\(ext) not found")
    }
    return try Data(contentsOf: url)
}

final class HokusaiTests: XCTestCase {
    func testLoadImageMetadata() async throws {
        let metadata = try await HokusaiTestRuntime.shared.withHokusai {
            let data = try loadFixtureData(named: "pixel", ext: "png")
            let image = try await Hokusai.image(from: data)
            return try image.metadata()
        }

        XCTAssertEqual(metadata.width, 1)
        XCTAssertEqual(metadata.height, 1)
        XCTAssertGreaterThanOrEqual(metadata.channels, 2)
        XCTAssertTrue(metadata.hasAlpha)
    }

    func testResizeImage() async throws {
        let resized = try await HokusaiTestRuntime.shared.withHokusai {
            let data = try loadFixtureData(named: "pixel", ext: "png")
            let image = try await Hokusai.image(from: data)
            return try image.resize(width: 8, height: 8)
        }

        XCTAssertEqual(try resized.width, 8)
        XCTAssertEqual(try resized.height, 8)
    }

    func testCompositeImage() async throws {
        let output = try await HokusaiTestRuntime.shared.withHokusai {
            let data = try loadFixtureData(named: "pixel", ext: "png")
            let base = try await Hokusai.image(from: data)
            let overlay = try await Hokusai.image(from: data)

            return try base.composite(
                overlay: overlay,
                x: 0,
                y: 0,
                options: CompositeOptions(mode: .over, opacity: 0.5)
            )
        }

        XCTAssertEqual(try output.width, 1)
        XCTAssertEqual(try output.height, 1)
    }
}
