import Foundation
import Testing
@testable import Hokusai

/// Lifecycle idempotency and concurrent-use behavior.
///
/// `Hokusai.shutdown()` is intentionally not exercised here: it permanently
/// tears down libvips for the whole process, so an in-process test would
/// poison every other test. Its contract (final, idempotent, re-init throws)
/// is enforced by the state machine in `VipsBackend` and exercised end-to-end
/// by every CLI invocation, which runs initialize → work → shutdown → exit.
@Suite struct LifecycleConcurrencyTests {
    init() throws {
        try Hokusai.initialize()
    }

    // MARK: - Initialization

    @Test func repeatedInitializationIsIdempotent() throws {
        try Hokusai.initialize()
        try Hokusai.initialize()
        try Hokusai.initialize()

        // The runtime must remain usable afterwards.
        let data = try loadFixtureData(named: "pixel", ext: "png")
        #expect(try Hokusai.image(from: data).width == 1)
    }

    @Test func shutdownRefusesToTearDownLiveImages() throws {
        let data = try loadFixtureData(named: "pixel", ext: "png")
        let image = try Hokusai.image(from: data)
        #expect(throws: HokusaiError.self) {
            try Hokusai.shutdown()
        }
        #expect(try image.width == 1)
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

    // MARK: - Concurrent image work

    @Test func concurrentLoadsAfterInitialization() async throws {
        let data = try loadFixtureData(named: "landscape-asym", ext: "jpg")
        let path = try fixturePath(named: "landscape-asym", ext: "jpg")

        try await withThrowingTaskGroup(of: Int.self) { group in
            for index in 0..<16 {
                group.addTask {
                    let image = index.isMultiple(of: 2)
                        ? try Hokusai.image(from: data)
                        : try Hokusai.image(from: path)
                    return try image.width
                }
            }
            for try await width in group {
                #expect(width == 320)
            }
        }
    }

    @Test func concurrentThumbnailsFromMultipleTasks() async throws {
        let data = try loadFixtureData(named: "landscape-asym", ext: "jpg")
        let path = try fixturePath(named: "landscape-asym", ext: "jpg")
        let shared = try Hokusai.image(from: path)

        try await withThrowingTaskGroup(of: (Int, Int).self) { group in
            for index in 0..<24 {
                group.addTask {
                    let thumb: HokusaiImage
                    switch index % 3 {
                    case 0: thumb = try Hokusai.thumbnail(from: path, width: 64)
                    case 1: thumb = try Hokusai.thumbnail(from: data, width: 64)
                    default: thumb = try shared.thumbnail(width: 64)
                    }
                    return (try thumb.width, try thumb.height)
                }
            }
            for try await (width, height) in group {
                #expect(width == 64)
                #expect(height == 40)
            }
        }
    }

    @Test func concurrentBufferEncodingOnSharedImage() async throws {
        let path = try fixturePath(named: "landscape-asym", ext: "jpg")
        let shared = try Hokusai.image(from: path)

        try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    try shared.resize(width: 64, height: 40)
                        .toBuffer(options: SaveOptions(format: .jpeg, quality: 85))
                }
            }
            for try await encoded in group {
                #expect(!encoded.isEmpty)
            }
        }
    }

    // MARK: - Wrapper lifetime churn

    @Test func repeatedWrapperCreationAndDestruction() throws {
        let data = try loadFixtureData(named: "landscape-asym", ext: "jpg")

        // Exercises pointer ownership: every iteration creates and releases a
        // loader image, a thumbnail image, and an encode buffer. A double free
        // or an unref of a borrowed pointer crashes this loop.
        for _ in 0..<200 {
            let image = try Hokusai.image(from: data)
            let thumb = try image.thumbnail(width: 32)
            _ = try thumb.toBuffer(options: SaveOptions(format: .jpeg, quality: 80))
        }
    }

    @Test func bufferSourceOutlivesTransientData() throws {
        // Regression test for buffer-lifetime ownership: the encoded bytes are
        // copied by the shim, so the image must stay decodable after the
        // original Data has been mutated and released.
        var transient = try loadFixtureData(named: "landscape-asym", ext: "jpg")
        let image = try Hokusai.image(from: transient)
        let thumb = try Hokusai.thumbnail(from: transient, width: 64)

        // Clobber and drop the original storage before pixels are pulled.
        transient.resetBytes(in: 0..<transient.count)
        transient = Data()

        #expect(try image.width == 320)
        #expect(try !image.toBuffer(options: SaveOptions(format: .png)).isEmpty)
        #expect(try thumb.width == 64)
        #expect(try !thumb.toBuffer(options: SaveOptions(format: .png)).isEmpty)
    }
}
