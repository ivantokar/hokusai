import Foundation
import Hokusai
import Testing

/// Documented operation semantics, checked against exact pixels.
@Suite struct OperationSemanticsTests {
    private let source = gradient(width: 8, height: 6)

    @Test func flipIsVerticalAndFlopIsHorizontal() async throws {
        let flipped = try await rasterize(source.pipeline().flip())
        expectPixels(flipped, match: Raster(width: 8, height: 6) { x, y in source.pixel(x, 5 - y) })
        let flopped = try await rasterize(source.pipeline().flop())
        expectPixels(flopped, match: Raster(width: 8, height: 6) { x, y in source.pixel(7 - x, y) })
    }

    @Test func extractCopiesExactlyTheRectangle() async throws {
        let cropped = try await rasterize(source.pipeline().extract(x: 2, y: 1, width: 4, height: 3))
        expectPixels(cropped, match: Raster(width: 4, height: 3) { x, y in source.pixel(x + 2, y + 1) })
    }

    @Test func rotationByQuarterTurnsMovesPixelsExactly() async throws {
        let turned = try await rasterize(source.pipeline().rotate(by: 90))
        // A clockwise quarter turn: the left column becomes the top row.
        expectPixels(turned, match: Raster(width: 6, height: 8) { x, y in source.pixel(y, 5 - x) })
    }

    @Test func resizeToTheSameSizeKeepsPixels() async throws {
        let same = try await rasterize(source.pipeline().resize(width: 8, height: 6, fit: .fill))
        expectPixels(same, match: source, .absolute(maxChannelDelta: 1))
    }

    @Test func resizingAFlatImageKeepsItFlat() async throws {
        let flat = Raster.solid(width: 40, height: 30, [200, 100, 50, 255])
        let small = try await rasterize(flat.pipeline().resize(width: 7, height: 5, fit: .fill))
        expectPixels(small, match: .solid(width: 7, height: 5, [200, 100, 50, 255]), .absolute(maxChannelDelta: 1))
    }

    @Test func grayscalePreservesAlphaAndRemovesColour() async throws {
        let translucent = Raster.solid(width: 3, height: 3, [255, 0, 0, 128])
        let grey = try await rasterize(translucent.pipeline().grayscale())
        for y in 0..<3 {
            for x in 0..<3 {
                let pixel = grey.pixel(x, y)
                #expect(pixel[0] == pixel[1] && pixel[1] == pixel[2])
                #expect(pixel[3] == 128)
            }
        }
    }

    @Test func flattenReplacesTransparencyWithTheBackground() async throws {
        let transparent = Raster.solid(width: 3, height: 3, [255, 0, 0, 0])
        let flat = try await rasterize(transparent.pipeline().flatten(background: .sRGB8(red: 0, green: 0, blue: 255)))
        expectPixels(flat, match: .solid(width: 3, height: 3, [0, 0, 255, 255]))
    }

    @Test func anOpaqueLayerOverwritesTheBaseWhereItLands() async throws {
        let base = Raster.solid(width: 6, height: 6, [10, 20, 30, 255])
        let layer = try Raster.solid(width: 2, height: 2, [200, 0, 0, 255]).pipeline()
        let result = try await rasterize(base.pipeline().composite([CompositeLayer(layer, placement: .at(x: 3, y: 1))]))
        let expected = Raster(width: 6, height: 6) { x, y in (3..<5).contains(x) && (1..<3).contains(y) ? [200, 0, 0, 255] : [10, 20, 30, 255] }
        expectPixels(result, match: expected)
    }

    @Test func gravityPlacementUsesInwardOffsets() async throws {
        let base = Raster.solid(width: 10, height: 10, [0, 0, 0, 255])
        let layer = try Raster.solid(width: 2, height: 2, [255, 255, 255, 255]).pipeline()
        let result = try await rasterize(base.pipeline().composite([CompositeLayer(layer, placement: .gravity(.southEast, offsetX: 1, offsetY: 2))]))
        let expected = Raster(width: 10, height: 10) { x, y in (7..<9).contains(x) && (6..<8).contains(y) ? [255, 255, 255, 255] : [0, 0, 0, 255] }
        expectPixels(result, match: expected)
    }

    @Test func branchesAreIndependentValues() async throws {
        let root = try source.pipeline()
        let narrow = try root.resize(width: 4, height: 3, fit: .fill)
        let flipped = root.flip()
        #expect(try await rasterize(root) == source)
        #expect(try await rasterize(narrow).width == 4)
        expectPixels(try await rasterize(flipped), match: Raster(width: 8, height: 6) { x, y in source.pixel(x, 5 - y) })
    }
}

/// Reordering must change the result: the evaluator may change how a pipeline
/// runs, never what the written order means.
@Suite struct OperationOrderTests {
    /// Pixels with a hard edge, so blur and resize do not commute.
    private let edges = Raster(width: 24, height: 16) { x, y in
        ((x / 4 + y / 4) % 2 == 0) ? [255, 255, 255, 255] : [0, 0, 0, 255]
    }

    @Test func blurThenResizeIsNotResizeThenBlur() async throws {
        let blurFirst = try await rasterize(edges.pipeline().blur(sigma: 2).resize(width: 12, height: 8, fit: .fill))
        let resizeFirst = try await rasterize(edges.pipeline().resize(width: 12, height: 8, fit: .fill).blur(sigma: 2))
        #expect(differ(blurFirst, resizeFirst))
    }

    @Test func rotateThenExtractIsNotExtractThenRotate() async throws {
        let source = gradient(width: 8, height: 6)
        let rotateFirst = try await rasterize(source.pipeline().rotate(by: 90).extract(x: 0, y: 0, width: 3, height: 3))
        let extractFirst = try await rasterize(source.pipeline().extract(x: 0, y: 0, width: 3, height: 3).rotate(by: 90))
        #expect(differ(rotateFirst, extractFirst))
    }

    @Test func trimThenResizeIsNotResizeThenTrim() async throws {
        let bordered = Raster(width: 40, height: 40) { x, y in
            (10..<30).contains(x) && (10..<30).contains(y) ? [0, 0, 0, 255] : [255, 255, 255, 255]
        }
        let trimFirst = try await bordered.pipeline().trim().resize(width: 10, height: 10, fit: .fill).png().data().info
        #expect((trimFirst.width, trimFirst.height) == (10, 10))
        let resizeFirst = try await bordered.pipeline().resize(width: 10, height: 10, fit: .fill).trim().png().data().info
        #expect((resizeFirst.width, resizeFirst.height) != (10, 10))
    }

    @Test func autoOrientThenExtractIsNotExtractThenAutoOrient() async throws {
        let source = gradient(width: 8, height: 6)
        let orientedFirst = try await rasterize(source.pipeline(orientation: 6).autoOrient().extract(x: 0, y: 0, width: 4, height: 2))
        let extractFirst = try await rasterize(source.pipeline(orientation: 6).extract(x: 0, y: 0, width: 4, height: 2).autoOrient())
        #expect(differ(orientedFirst, extractFirst))
    }

    @Test func normalizeThenTintIsNotTintThenNormalize() async throws {
        let source = gradient(width: 16, height: 16)
        let tint = Color(red: 0.9, green: 0.4, blue: 0.1)
        let normalizeFirst = try await rasterize(source.pipeline().normalize().tint(tint))
        let tintFirst = try await rasterize(source.pipeline().tint(tint).normalize())
        #expect(differ(normalizeFirst, tintFirst))
    }
}

/// EXIF orientation 1...8: metadata reports it, `autoOrient()` applies it, and
/// nothing downstream changes what `metadata()` says about the source.
@Suite struct OrientationTests {
    /// The displayed pixel at (dx, dy) for a stored `width × height` image.
    private func displayed(_ orientation: Int, stored: Raster, _ dx: Int, _ dy: Int) -> [UInt8] {
        let w = stored.width, h = stored.height
        switch orientation {
        case 1: return stored.pixel(dx, dy)
        case 2: return stored.pixel(w - 1 - dx, dy)
        case 3: return stored.pixel(w - 1 - dx, h - 1 - dy)
        case 4: return stored.pixel(dx, h - 1 - dy)
        case 5: return stored.pixel(dy, dx)
        case 6: return stored.pixel(dy, h - 1 - dx)
        case 7: return stored.pixel(w - 1 - dy, h - 1 - dx)
        default: return stored.pixel(w - 1 - dy, dx)
        }
    }

    @Test(arguments: 1...8)
    func autoOrientDisplaysEveryOrientationUpright(orientation: Int) async throws {
        let stored = gradient(width: 4, height: 3)
        let swaps = orientation >= 5
        let size = swaps ? (3, 4) : (4, 3)
        let expected = Raster(width: size.0, height: size.1) { x, y in displayed(orientation, stored: stored, x, y) }

        let result = try await rasterize(stored.pipeline(orientation: orientation).autoOrient())
        expectPixels(result, match: expected)
    }

    @Test(arguments: 1...8)
    func metadataReportsOrientationAndOrientedSize(orientation: Int) async throws {
        let image = try gradient(width: 4, height: 3).pipeline(orientation: orientation)
        let metadata = try await image.metadata()

        #expect(metadata.orientation?.rawValue == orientation)
        #expect(metadata.width == 4 && metadata.height == 3, "stored dimensions are unchanged")
        let oriented = metadata.orientedSize
        #expect((oriented.width, oriented.height) == (orientation >= 5 ? (3, 4) : (4, 3)))
    }

    @Test func downstreamTransformsDoNotChangeSourceMetadata() async throws {
        let image = try gradient(width: 4, height: 3).pipeline(orientation: 6)
        let before = try await image.metadata()
        let after = try await image.autoOrient().resize(width: 2, fit: .inside).flip().metadata()
        #expect(before == after)
    }
}
