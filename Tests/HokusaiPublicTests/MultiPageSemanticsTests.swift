import Foundation
import Hokusai
import Testing

/// The multi-page and animation contract (#27), black box: exactly one page is
/// read, page count is not animation, and an output is always one page.
/// Frames are compared as decoded pixels, never as encoded bytes.
@Suite struct MultiPageSemanticsTests {
    private func source(_ name: String, _ ext: String, page: Int? = nil, limits: InputLimits = InputLimits()) throws -> Hokusai {
        try Hokusai(url: fixtureURL(named: name, ext: ext), options: InputOptions(page: page, limits: limits))
    }

    private func frames(_ name: String, _ ext: String, count: Int) async throws -> [Raster] {
        var result: [Raster] = []
        for page in 0..<count {
            result.append(try await rasterize(source(name, ext, page: page)))
        }
        return result
    }

    // MARK: - Animated sources

    @Test(arguments: ["gif", "webp"])
    func eachFrameOfAnAnimationCanBeSelected(ext: String) async throws {
        let first = try await rasterize(source("animated", ext))
        let all = try await frames("animated", ext, count: 3)

        expectPixels(all[0], match: first)   // no page means the first frame
        #expect(differ(all[0], all[1]) && differ(all[1], all[2]) && differ(all[0], all[2]), "the three frames differ")
    }

    @Test(arguments: ["gif", "webp"])
    func aFrameBeyondTheEndIsAnInvalidOptionNamingPage(ext: String) async throws {
        do {
            _ = try await source("animated", ext, page: 3).png().data()
            Issue.record("expected the out-of-range frame to fail")
        } catch HokusaiError.invalidOption(let name, _) {
            #expect(name == "page")
        }
    }

    @Test(arguments: ["gif", "webp"])
    func aSelectedFrameStillDescribesTheWholeAnimation(ext: String) async throws {
        let metadata = try await source("animated", ext, page: 2).metadata()
        #expect(metadata.pages.count == 3)
        #expect(metadata.isAnimated)
        #expect(metadata.animation?.frameDelays.count == 3)
    }

    // MARK: - Outputs are one page

    @Test func transformingAnAnimationKeepsOnlyTheSelectedFrame() async throws {
        let output = try await source("animated", "webp").resize(width: 8, fit: .fill).webp().data()
        let described = try await Hokusai(data: output.data).metadata()

        #expect(described.pages.count == 1)
        #expect(!described.isAnimated)
        #expect(output.info.width == 8)
    }

    @Test func eachSelectedFrameSurvivesTransformationAsItsOwnPicture() async throws {
        let outputs = try await (0..<3).asyncMap { page in
            try await rasterize(source("animated", "webp", page: page).resize(width: 8, fit: .fill).png())
        }
        #expect(differ(outputs[0], outputs[1]) && differ(outputs[1], outputs[2]))
    }

    @Test(.enabled(if: (try? Hokusai.capabilities().canEncode(.gif)) ?? false, "GIF encoding not available in this libvips build"))
    func reencodingAnAnimatedGIFProducesOneFrame() async throws {
        let output = try await source("animated", "gif").resize(width: 8, fit: .fill).gif().data()
        let described = try await Hokusai(data: output.data).metadata()

        #expect(described.pages.count == 1)
        #expect(!described.isAnimated)
    }

    @Test func aPagedDocumentEncodesToASinglePageImage() async throws {
        let output = try await source("multipage", "tif").tiff().data()
        #expect(try await Hokusai(data: output.data).metadata().pages.count == 1)
    }

    @Test func eachPageOfAPagedDocumentIsItsOwnPicture() async throws {
        let pages = try await frames("multipage", "tif", count: 3)
        #expect(differ(pages[0], pages[1]) && differ(pages[1], pages[2]) && differ(pages[0], pages[2]))
        // The fixture's pages are flat greys at 30, 120 and 210.
        for (page, level) in zip(pages, [30, 120, 210]) {
            #expect(page.pixel(0, 0)[0] == UInt8(level))
        }
    }

    @Test func aPageBeyondTheEndOfADocumentIsAnInvalidOption() async throws {
        do {
            _ = try await source("multipage", "tif", page: 3).png().data()
            Issue.record("expected the out-of-range page to fail")
        } catch HokusaiError.invalidOption(let name, _) {
            #expect(name == "page")
        }
    }

    // MARK: - Page count is not animation

    @Test func pageCountAloneNeverMakesAnImageAnimated() async throws {
        let tiff = try await source("multipage", "tif").metadata()
        #expect(tiff.pages.count == 3)
        #expect(tiff.animation == nil && !tiff.isAnimated)
    }

    @Test func aSinglePageSourceRejectsAnyOtherPage() async throws {
        do {
            _ = try await source("pixel", "png", page: 1).png().data()
            Issue.record("expected page 1 of a single-page image to fail")
        } catch HokusaiError.unsupported, HokusaiError.invalidOption {
            // Either typed refusal is acceptable; silently returning page 0 is not.
        }
    }

    @Test func pixelLimitsApplyToTheSelectedPageAlone() async throws {
        let limits = InputLimits(maxPixels: 16 * 16)
        let output = try await source("multipage", "tif", page: 2, limits: limits).png().data()
        #expect(output.info.width == 16)
    }

    @Test func negativePagesAreAnInvalidOptionNamingPage() throws {
        do {
            _ = try source("multipage", "tif", page: -1)
            Issue.record("expected a negative page to be rejected")
        } catch HokusaiError.invalidOption(let name, _) {
            #expect(name == "page")
        }
    }
}

extension Sequence {
    fileprivate func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var results: [T] = []
        for element in self { results.append(try await transform(element)) }
        return results
    }
}
