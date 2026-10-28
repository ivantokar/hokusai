import Foundation
import Testing
@testable import Hokusai

/// The multi-page and animation contract (#27): exactly one page is read,
/// page count is not animation, and an output is always one page.
@Suite struct MultiPageTests {
    init() throws { try Hokusai.initialize() }

    private func url(_ name: String, _ ext: String) throws -> URL {
        try fixtureURL(named: name, ext: ext)
    }

    /// The PNG bytes of one page, as a stand-in for "which frame is this".
    private func frame(_ name: String, _ ext: String, page: Int?) async throws -> Data {
        try await Hokusai(url: url(name, ext), options: InputOptions(page: page)).png().data().data
    }

    // MARK: - Animated sources

    @Test(arguments: ["gif", "webp"])
    func eachFrameOfAnAnimationCanBeSelected(ext: String) async throws {
        let first = try await frame("animated", ext, page: nil)
        let frames = try await (0..<3).asyncMap { try await frame("animated", ext, page: $0) }

        #expect(frames[0] == first, "no page means the first frame")
        #expect(Set(frames).count == 3, "the three frames differ")
    }

    @Test(arguments: ["gif", "webp"])
    func aFrameBeyondTheEndIsAnInvalidOption(ext: String) async throws {
        let image = try Hokusai(url: url("animated", ext), options: InputOptions(page: 3))
        do {
            _ = try await image.png().data()
            Issue.record("expected the out-of-range frame to fail")
        } catch HokusaiError.invalidOption(let name, let reason) {
            #expect(name == "page")
            #expect(reason.contains("3 pages"))
        }
    }

    @Test(arguments: ["gif", "webp"])
    func aSelectedFrameStillDescribesTheWholeAnimation(ext: String) async throws {
        let metadata = try await Hokusai(url: url("animated", ext), options: InputOptions(page: 2)).metadata()
        #expect(metadata.pages.count == 3)
        #expect(metadata.isAnimated)
        #expect(metadata.animation?.frameDelays.count == 3)
    }

    // MARK: - Outputs are one page

    @Test func transformingAnAnimationKeepsOnlyTheSelectedFrame() async throws {
        let output = try await Hokusai(url: url("animated", "webp")).resize(width: 8, fit: .fill).webp().data()
        let described = try await Hokusai(data: output.data).metadata()

        #expect(described.pages.count == 1)
        #expect(!described.isAnimated)
        #expect(output.info.width == 8)
    }

    @Test(.enabled(if: (try? Hokusai.capabilities().canEncode(.gif)) ?? false, "GIF encoding not available in this libvips build"))
    func reencodingAnAnimatedGIFProducesOneFrame() async throws {
        let output = try await Hokusai(url: url("animated", "gif")).resize(width: 8, fit: .fill).gif().data()
        let described = try await Hokusai(data: output.data).metadata()

        #expect(described.pages.count == 1)
        #expect(!described.isAnimated)
    }

    @Test func aPagedDocumentEncodesToASinglePageImage() async throws {
        let output = try await Hokusai(url: url("multipage", "tif")).tiff().data()
        let described = try await Hokusai(data: output.data).metadata()
        #expect(described.pages.count == 1)
    }

    @Test func eachPageOfAPagedDocumentCanBeEncodedSeparately() async throws {
        let outputs = try await (0..<3).asyncMap {
            try await Hokusai(url: url("multipage", "tif"), options: InputOptions(page: $0)).png().data().data
        }
        #expect(Set(outputs).count == 3)
    }

    // MARK: - Page count is not animation

    @Test func pageCountAloneNeverMakesAnImageAnimated() async throws {
        let tiff = try await Hokusai(url: url("multipage", "tif")).metadata()
        #expect(tiff.pages.count == 3)
        #expect(tiff.animation == nil)
        #expect(!tiff.isAnimated)
    }

    @Test func aPageLimitedDecodeNeverLoadsMoreThanOnePage() async throws {
        // Pixel limits apply to the selected page, so a many-page source
        // costs one page of pixels; the all-page cost is never paid.
        let limits = InputLimits(maxPixels: 16 * 16)
        let output = try await Hokusai(url: url("multipage", "tif"), options: InputOptions(page: 2, limits: limits)).png().data()
        #expect(output.info.width == 16)
    }
}

extension Sequence {
    fileprivate func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var results: [T] = []
        for element in self { results.append(try await transform(element)) }
        return results
    }
}
