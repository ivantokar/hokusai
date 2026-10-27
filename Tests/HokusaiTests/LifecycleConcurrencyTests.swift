import Foundation
import Testing
@testable import Hokusai

/// Lifecycle idempotency and concurrent-use behavior.
///
/// libvips is process-scoped: it is initialized at most once and never torn
/// down, so these tests cover repeated and concurrent initialization, and
/// concurrent evaluation of pipelines that share a source.
@Suite struct LifecycleConcurrencyTests {
    init() throws {
        try Hokusai.initialize()
    }

    // MARK: - Initialization

    @Test func repeatedInitializationIsIdempotent() async throws {
        try Hokusai.initialize()
        try Hokusai.initialize()
        try Hokusai.initialize()

        // The runtime must remain usable afterwards.
        let data = try loadFixtureData(named: "pixel", ext: "png")
        let metadata = try await Hokusai(data: data).metadata()
        #expect(metadata.width == 1)
    }

    @Test func concurrentInitializationDoesNotRace() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<32 {
                group.addTask {
                    try Hokusai.initialize()
                }
            }
            try await group.waitForAll()
        }
    }

    // MARK: - Concurrent pipeline work

    @Test func concurrentLoadsAfterInitialization() async throws {
        let data = try loadFixtureData(named: "landscape-asym", ext: "jpg")
        let url = try fixtureURL(named: "landscape-asym", ext: "jpg")

        try await withThrowingTaskGroup(of: Int.self) { group in
            for index in 0..<16 {
                group.addTask {
                    let image = index.isMultiple(of: 2) ? try Hokusai(data: data) : try Hokusai(url: url)
                    return try await image.metadata().width
                }
            }
            for try await width in group {
                #expect(width == 320)
            }
        }
    }

    @Test func concurrentResizesFromOneSharedPipeline() async throws {
        let url = try fixtureURL(named: "landscape-asym", ext: "jpg")
        let shared = try Hokusai(url: url)

        try await withThrowingTaskGroup(of: (Int, Int).self) { group in
            for _ in 0..<24 {
                group.addTask {
                    let output = try await shared.resize(width: 64).png().data()
                    return (output.info.width, output.info.height)
                }
            }
            for try await (width, height) in group {
                #expect(width == 64)
                #expect(height == 40)
            }
        }
    }

    @Test func concurrentEncodingOfOneSharedPipeline() async throws {
        let url = try fixtureURL(named: "landscape-asym", ext: "jpg")
        let shared = try Hokusai(url: url).resize(width: 64, height: 40)

        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<16 {
                group.addTask { try await shared.jpeg(quality: 85).data().data.count }
            }
            for try await size in group {
                #expect(size > 0)
            }
        }
    }

    // MARK: - Native ownership churn

    @Test func repeatedPipelineCreationAndEvaluation() async throws {
        let data = try loadFixtureData(named: "landscape-asym", ext: "jpg")

        // Exercises pointer ownership: every iteration opens a source, lowers
        // a resize, and encodes. A double free or an unref of a borrowed
        // pointer crashes this loop.
        for _ in 0..<200 {
            _ = try await Hokusai(data: data).resize(width: 32).jpeg(quality: 80).data()
        }
    }

    @Test func bufferSourceOutlivesTransientData() async throws {
        // The pipeline keeps its own copy of the encoded bytes, so it must
        // stay decodable after the caller's Data has been mutated and released.
        var transient = try loadFixtureData(named: "landscape-asym", ext: "jpg")
        let image = try Hokusai(data: transient)

        // Clobber and drop the original storage before pixels are pulled.
        transient.resetBytes(in: 0..<transient.count)
        transient = Data()

        let metadata = try await image.metadata()
        #expect(metadata.width == 320)
        let output = try await image.resize(width: 64).png().data()
        #expect(output.info.width == 64)
    }
}
