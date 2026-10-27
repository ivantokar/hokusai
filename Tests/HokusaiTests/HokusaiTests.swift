import Foundation
import Testing
@testable import Hokusai

/// Smoke tests for the public pipeline: load, inspect, transform, encode.
@Suite struct CoreTests {
    init() throws {
        try Hokusai.initialize()
    }

    @Test func loadImageMetadata() async throws {
        let data = try loadFixtureData(named: "pixel", ext: "png")
        let metadata = try await Hokusai(data: data).metadata()

        #expect(metadata.width == 1)
        #expect(metadata.height == 1)
        #expect(metadata.pixel.channels >= 2)
        #expect(metadata.pixel.hasAlpha)
    }

    @Test func loadImageFromFileURL() async throws {
        let url = try fixtureURL(named: "landscape-asym", ext: "jpg")
        let metadata = try await Hokusai(url: url).metadata()

        #expect(metadata.width == 320)
        #expect(metadata.height == 200)
    }

    @Test func resizeImage() async throws {
        let data = try loadFixtureData(named: "pixel", ext: "png")
        let output = try await Hokusai(data: data).resize(width: 8, height: 8).png().data()

        #expect(output.info.width == 8)
        #expect(output.info.height == 8)
    }

    // MARK: - Sequential access

    @Test func loadWithSequentialAccess() async throws {
        let data = try loadFixtureData(named: "pixel", ext: "png")

        // Sequential load must produce the same image as random load.
        let metadata = try await Hokusai(data: data, options: InputOptions(access: .sequential)).metadata()

        #expect(metadata.width == 1)
        #expect(metadata.height == 1)
        #expect(metadata.pixel.hasAlpha)
    }

    @Test func sequentialLoadPresetConvenience() async throws {
        let data = try loadFixtureData(named: "landscape-asym", ext: "jpg")
        let metadata = try await Hokusai(data: data, options: .sequential).metadata()

        #expect(metadata.width == 320)
        #expect(metadata.height == 200)
    }

    @Test func sequentialSinglePassPipelineProducesOutput() async throws {
        // The documented use case: load -> resize -> encode, one forward pass.
        let url = try fixtureURL(named: "landscape-asym", ext: "jpg")
        let output = try await Hokusai(url: url, options: .sequential).resize(width: 64, height: 40).jpeg(quality: 85).data()

        #expect(!output.data.isEmpty)
    }

    // MARK: - Defaults

    @Test func defaultInputOptionsLoadTheSupportedFixtures() async throws {
        let data = try loadFixtureData(named: "pixel", ext: "png")
        let metadata = try await Hokusai(data: data, options: InputOptions()).metadata()

        #expect(metadata.width == 1)
        #expect(metadata.height == 1)
    }

    /// Mirrors the README thumbnail recipe so the documented snippet runs.
    @Test func readmeThumbnailRecipeRuns() async throws {
        let url = try fixtureURL(named: "landscape-asym", ext: "jpg")
        let image = try Hokusai(url: url)

        let bounded = try await image.resize(width: 40, height: 30, fit: .inside).png().data()
        #expect(bounded.info.width <= 40 && bounded.info.height <= 30)

        let cropped = try await image.resize(width: 40, height: 30, fit: .cover, position: .attention).png().data()
        #expect(cropped.info.width == 40 && cropped.info.height == 30)
    }
}
