import Foundation
import XCTest
@testable import Hokusai

private actor HokusaiTestRuntime {
    static let shared = HokusaiTestRuntime()
    private var isInitialized = false

    func ensureInitialized() throws {
        if !isInitialized {
            try Hokusai.initialize()
            isInitialized = true
        }
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
        try await HokusaiTestRuntime.shared.ensureInitialized()
        let data = try loadFixtureData(named: "pixel", ext: "png")
        let image = try await Hokusai.image(from: data)
        let metadata = try image.metadata()

        XCTAssertEqual(metadata.width, 1)
        XCTAssertEqual(metadata.height, 1)
        XCTAssertGreaterThanOrEqual(metadata.channels, 2)
        XCTAssertTrue(metadata.hasAlpha)
    }

    func testResizeImage() async throws {
        try await HokusaiTestRuntime.shared.ensureInitialized()
        let data = try loadFixtureData(named: "pixel", ext: "png")
        let image = try await Hokusai.image(from: data)
        let resized = try image.resize(width: 8, height: 8)

        XCTAssertEqual(try resized.width, 8)
        XCTAssertEqual(try resized.height, 8)
    }

    func testCompositeImage() async throws {
        try await HokusaiTestRuntime.shared.ensureInitialized()
        let data = try loadFixtureData(named: "pixel", ext: "png")
        let base = try await Hokusai.image(from: data)
        let overlay = try await Hokusai.image(from: data)
        let output = try base.composite(
            overlay: overlay,
            x: 0,
            y: 0,
            options: CompositeOptions(mode: .over, opacity: 0.5)
        )

        XCTAssertEqual(try output.width, 1)
        XCTAssertEqual(try output.height, 1)
    }

    func testDrawTextWithVipsBackend() async throws {
        try await HokusaiTestRuntime.shared.ensureInitialized()
        let data = try loadFixtureData(named: "pixel", ext: "png")
        let image = try await Hokusai.image(from: data)
        let canvas = try image.resize(width: 256, height: 128)

        var options = TextOptions()
        options.font = "sans"
        options.fontSize = 20
        options.color = [255, 255, 255, 255]
        options.strokeColor = [0, 0, 0, 255]
        options.strokeWidth = 1
        options.shadowOffset = (x: 1, y: 1)
        options.shadowColor = [0, 0, 0, 150]

        let output = try canvas.drawText("A", x: 24, y: 48, options: options)
        let png = try output.toBuffer(options: SaveOptions(format: .png))

        XCTAssertEqual(try output.width, 256)
        XCTAssertEqual(try output.height, 128)
        XCTAssertFalse(png.isEmpty)
    }
}
