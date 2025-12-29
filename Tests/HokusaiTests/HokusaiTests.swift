import Foundation
import Testing
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

@Test("Load image from buffer and read metadata")
func loadImageMetadata() async throws {
    let metadata = try await HokusaiTestRuntime.shared.withHokusai {
        let data = try loadFixtureData(named: "pixel", ext: "png")
        let image = try await Hokusai.image(from: data)
        return try image.metadata()
    }

    #expect(metadata.width == 1)
    #expect(metadata.height == 1)
    #expect(metadata.channels >= 2)
    #expect(metadata.hasAlpha == true)
}

@Test("Resize returns expected dimensions")
func resizeImage() async throws {
    let resized = try await HokusaiTestRuntime.shared.withHokusai {
        let data = try loadFixtureData(named: "pixel", ext: "png")
        let image = try await Hokusai.image(from: data)
        return try image.resize(width: 8, height: 8)
    }

    #expect(try resized.width == 8)
    #expect(try resized.height == 8)
}

@Test("Composite returns base image size")
func compositeImage() async throws {
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

    #expect(try output.width == 1)
    #expect(try output.height == 1)
}
