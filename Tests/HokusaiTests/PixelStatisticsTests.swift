import Foundation
import Testing
@testable import Hokusai

/// `stats()` measures the pixels of the current pipeline (#24).
@Suite struct PixelStatisticsTests {
    init() throws { try Hokusai.initialize() }

    // MARK: - Helpers

    private func fixture(_ name: String, _ ext: String = "png") throws -> Hokusai {
        try Hokusai(url: fixtureURL(named: name, ext: ext))
    }

    private func channel(_ stats: ImageStatistics, _ kind: ChannelStatistics.Kind) throws -> ChannelStatistics {
        try #require(stats.channel(kind), "missing \(kind) channel")
    }

    private func near(_ a: Double, _ b: Double, _ tolerance: Double = 0.001) -> Bool { abs(a - b) <= tolerance }

    // MARK: - Per-channel statistics

    @Test func channelStatisticsMatchKnownPixels() async throws {
        // Three pixels, each (200, 100, 50), with alpha 255, 128 and 0.
        let stats = try await fixture("rgba-alpha").stats()
        #expect(stats.channels.map(\.kind) == [.red, .green, .blue, .alpha])

        let red = try channel(stats, .red)
        #expect(red.minimum == 200 && red.maximum == 200 && red.mean == 200)
        #expect(red.standardDeviation == 0)
        #expect(red.sum == 600 && red.sumOfSquares == 3 * 200 * 200)

        let green = try channel(stats, .green)
        #expect(green.mean == 100 && green.sum == 300)
        #expect(try channel(stats, .blue).mean == 50)

        let alpha = try channel(stats, .alpha)
        #expect(alpha.minimum == 0 && alpha.maximum == 255)
        #expect(alpha.minimumLocation == .init(x: 2, y: 0))
        #expect(alpha.maximumLocation == .init(x: 0, y: 0))
        #expect(near(alpha.mean, (255 + 128 + 0) / 3.0))
        #expect(alpha.sum == 383)
        // Sample deviation (n − 1) of 255, 128, 0, as libvips reports it.
        let values: [Double] = [255, 128, 0]
        let mean = values.reduce(0, +) / 3
        let squares: Double = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +)
        let sampleDeviation: Double = (squares / 2).squareRoot()
        #expect(near(alpha.standardDeviation, sampleDeviation, 0.05))
    }

    @Test func locationsPointAtTheExtremes() async throws {
        let stats = try await fixture("stats-colors").stats()
        // Columns 0...5 are red (250, 10, 10) and 6...7 are blue (10, 10, 250).
        let red = try channel(stats, .red)
        #expect(red.maximum == 250 && red.minimum == 10)
        #expect(red.maximumLocation.x <= 5 && red.minimumLocation.x >= 6)
        let blue = try channel(stats, .blue)
        #expect(blue.maximumLocation.x >= 6 && blue.minimumLocation.x <= 5)
        let expectedMean: Double = (6.0 * 250.0 + 2.0 * 10.0) / 8.0
        #expect(near(red.mean, expectedMean))
    }

    @Test func greyscaleImagesHaveGreyChannels() async throws {
        let stats = try await fixture("pixel").stats()
        #expect(stats.channels.map(\.kind) == [.grey, .alpha])
        #expect(stats.dominantColor != nil)
    }

    @Test func aSinglePixelHasNoSpread() async throws {
        let stats = try await fixture("pixel").stats()
        #expect(stats.channels.allSatisfy { $0.standardDeviation == 0 })
        #expect(stats.sharpness == 0)
        let again = try await fixture("pixel").stats()
        #expect(stats == again, "no NaN, so the value compares equal")
    }

    @Test func wideAndCMYKSourcesAreMeasuredAsEightBit() async throws {
        let sixteen = try await fixture("rgb16").stats()
        #expect(sixteen.channels.count == 3)
        #expect(sixteen.channels.allSatisfy { $0.maximum <= 255 })

        let cmyk = try await fixture("cmyk", "jpg").stats()
        #expect(cmyk.channels.map(\.kind) == [.red, .green, .blue])
    }

    // MARK: - The current pipeline, not the source

    @Test func statsDescribeTheTransformedPipeline() async throws {
        let source = try fixture("stats-colors")
        let original = try await source.stats()
        let blueOnly = try await source.extract(x: 6, y: 0, width: 2, height: 4).stats()

        #expect(try channel(original, .blue).minimum == 10)
        // The crop contains only blue pixels, so its extremes differ from the source's.
        let blue = try channel(blueOnly, .blue)
        #expect(blue.minimum == 250 && blue.maximum == 250)
        #expect(try channel(blueOnly, .red).maximum == 10)
    }

    @Test func aResizedBranchDoesNotChangeTheSourceBranch() async throws {
        let base = try fixture("landscape-asym", "jpg")
        async let whole = base.stats()
        async let blurred = base.blur(sigma: 4).stats()
        async let cropped = base.extract(x: 0, y: 0, width: 10, height: 10).stats()
        let (a, b, c) = try await (whole, blurred, cropped)

        #expect(a.sharpness > b.sharpness)
        #expect(c.channels.allSatisfy { $0.maximum <= 255 })
        #expect(a != b && a != c)
    }

    @Test func analysisDoesNotConsumeThePipeline() async throws {
        let pipeline = try fixture("landscape-asym", "jpg").resize(width: 80).png()
        let before = try await pipeline.data()
        _ = try await pipeline.stats()
        let after = try await pipeline.data()
        #expect(before.data == after.data)
    }

    // MARK: - Opacity

    @Test func opacityFollowsTheAlphaBand() async throws {
        #expect(try await fixture("landscape-asym", "jpg").stats().isOpaque)
        #expect(try await fixture("stats-colors").stats().isOpaque)
        #expect(try await fixture("rgba-alpha").stats().isOpaque == false)
    }

    // MARK: - Entropy

    @Test func entropyIsExactForKnownDistributions() async throws {
        // Half black, half white: two equally likely levels is one bit.
        let halves = try await fixture("stats-halves").stats()
        #expect(near(halves.entropy, 1.0))

        // One flat tone has no entropy.
        let flat = try await fixture("stats-halves").extract(x: 0, y: 0, width: 4, height: 8).stats()
        #expect(near(flat.entropy, 0))
    }

    @Test func entropyRisesWithDetail() async throws {
        let photo = try fixture("landscape-asym", "jpg")
        let whole = try await photo.stats().entropy
        // The noisy block (x 10..110, y 50..150) is far richer than the black margin.
        let noise = try await photo.extract(x: 20, y: 60, width: 80, height: 80).stats().entropy
        let margin = try await photo.extract(x: 200, y: 10, width: 80, height: 30).stats().entropy
        #expect(noise > whole && whole > margin)
        #expect(noise <= 8 && margin >= 0)
    }

    @Test func entropyIgnoresAlpha() async throws {
        // The three pixels share one colour and differ only in alpha.
        let stats = try await fixture("rgba-alpha").stats()
        #expect(near(stats.entropy, 0))
    }

    // MARK: - Sharpness

    @Test func sharpnessSeparatesCrispFromBlurred() async throws {
        let photo = try fixture("landscape-asym", "jpg")
        let crisp = try await photo.stats().sharpness
        let soft = try await photo.blur(sigma: 2).stats().sharpness
        let softer = try await photo.blur(sigma: 6).stats().sharpness
        #expect(crisp > soft && soft > softer)
        #expect(softer >= 0)
    }

    @Test func aFlatImageHasNoSharpness() async throws {
        let flat = try await fixture("stats-halves").extract(x: 0, y: 0, width: 4, height: 8).stats()
        #expect(near(flat.sharpness, 0))
        let edge = try await fixture("stats-halves").stats().sharpness
        #expect(edge > 0, "a hard edge registers")
    }

    // MARK: - Dominant colour

    @Test func dominantColourIsTheFullestColourGroup() async throws {
        // Red fills three quarters of the image. 250 falls in the 15th group of
        // 16, whose centre is 248; 10 falls in the 0th, centred on 8.
        let stats = try await fixture("stats-colors").stats()
        let colour = try #require(stats.dominantColor)
        #expect(near(colour.red, 248 / 255.0, 0.002))
        #expect(near(colour.green, 8 / 255.0, 0.002))
        #expect(near(colour.blue, 8 / 255.0, 0.002))

        let blue = try #require(try await fixture("stats-colors").extract(x: 6, y: 0, width: 2, height: 4).stats().dominantColor)
        #expect(near(blue.blue, 248 / 255.0, 0.002) && near(blue.red, 8 / 255.0, 0.002))
    }

    @Test func dominantColourOfAGreyImageIsGrey() async throws {
        let colour = try #require(try await fixture("pixel").stats().dominantColor)
        #expect(near(colour.red, colour.green, 0.001) && near(colour.green, colour.blue, 0.001))
    }

    // MARK: - Failures and cancellation

    @Test func aMissingFileIsAReadIOError() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("missing-\(UUID().uuidString).png")
        do {
            _ = try await Hokusai(url: url).stats()
            Issue.record("expected a read error")
        } catch HokusaiError.io(_, let operation, _) {
            #expect(operation == .read)
        }
    }

    @Test func aSourceThatCannotBeDecodedIsADecodeError() async throws {
        do {
            _ = try await fixture("truncated", "jpg").stats()
            Issue.record("expected a decode error")
        } catch HokusaiError.decode(let context) {
            #expect(context.operation == "decode truncated.jpg")
        }
    }

    @Test func cancellationStopsAnExpensiveAnalysis() async throws {
        let expensive = try Hokusai(data: loadFixtureData(named: "landscape-asym", ext: "jpg"))
            .resize(width: 12000, height: 7500, fit: .fill)
            .blur(sigma: 50)

        let task = Task { try await expensive.stats() }
        try await Task.sleep(nanoseconds: 200_000_000)
        let cancelledAt = Date()
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch is CancellationError {
            #expect(Date().timeIntervalSince(cancelledAt) < 1.5)
        }
    }

    @Test func analysisIsSafeUnderConcurrency() async throws {
        let base = try fixture("landscape-asym", "jpg")
        let expected = try await base.resize(width: 100).stats()
        let whole = try await base.stats()

        try await withThrowingTaskGroup(of: Bool.self) { group in
            for index in 0..<24 {
                group.addTask {
                    if index.isMultiple(of: 2) {
                        let stats = try await base.resize(width: 100).stats()
                        // Everything but sharpness and tied extreme locations is exact.
                        func values(_ s: ImageStatistics) -> [[Double]] {
                            s.channels.map { [$0.minimum, $0.maximum, $0.sum, $0.sumOfSquares, $0.mean, $0.standardDeviation] }
                        }
                        return values(stats) == values(expected) && stats.isOpaque == expected.isOpaque
                            && stats.entropy == expected.entropy && stats.dominantColor == expected.dominantColor
                            && abs(stats.sharpness - expected.sharpness) < 1e-6
                    }
                    return try await base.blur(sigma: 3).stats().sharpness < whole.sharpness
                }
            }
            for try await ok in group { #expect(ok) }
        }
    }
}
