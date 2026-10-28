import Foundation
import Hokusai
import Testing

/// The helpers are the suite's oracle, so they are verified first.
@Suite struct RasterSupportTests {
    @Test func aRasterSurvivesTheTIFFRoundTripThroughHokusai() async throws {
        let source = gradient(width: 7, height: 5)
        let result = try await rasterize(source.pipeline())
        expectPixels(result, match: source)
    }

    @Test func comparisonReportsFirstAndWorstMismatch() {
        var changed = Raster.solid(width: 4, height: 3, [10, 10, 10, 255])
        let expected = changed
        changed.pixels[(1 * 4 + 2) * 4] = 14   // (2, 1), delta 4
        changed.pixels[(2 * 4 + 3) * 4 + 1] = 30   // (3, 2), delta 20
        let diff = difference(expected, changed)

        #expect(diff.firstMismatch?.x == 2 && diff.firstMismatch?.y == 1)
        #expect(diff.worstDelta == 20)
        #expect(diff.worst?.x == 3 && diff.worst?.y == 2)
        #expect(diff.description.contains("first mismatch at (2, 1)"))
    }

    @Test func differentSizesAreReportedAsSuch() {
        let diff = difference(.solid(width: 2, height: 2, [0, 0, 0, 255]), .solid(width: 3, height: 2, [0, 0, 0, 255]))
        #expect(diff.sizeMismatch != nil)
    }

    @Test func publicValuesThatPromiseSendableAre() {
        func requireSendable<T: Sendable>(_: T.Type) {}
        requireSendable(Hokusai.self)
        requireSendable(InputOptions.self)
        requireSendable(InputLimits.self)
        requireSendable(Encoder.self)
        requireSendable(Output.self)
        requireSendable(OutputInfo.self)
        requireSendable(ImageMetadata.self)
        requireSendable(HokusaiError.self)
        requireSendable(RuntimeConfiguration.self)
        requireSendable(RuntimeCapabilities.self)
        requireSendable(RuntimeStatus.self)
        requireSendable(CompositeLayer.self)
        requireSendable(Placement.self)
        requireSendable(MetadataPolicy.self)
        requireSendable(TextStyle.self)
    }
}
