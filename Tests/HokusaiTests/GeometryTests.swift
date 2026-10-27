import Foundation
import Testing
import CVips
@testable import Hokusai

/// Geometry operations on the evaluator (#35).
///
/// Fixtures: `landscape-asym.jpg` is 320×200 and `portrait-asym.jpg` 200×320,
/// both flat black with a noise block; `orientation-6.jpg` is 120×80 with EXIF
/// orientation 6; `rgba-alpha.png` carries an alpha channel.
@Suite struct GeometryTests {
    init() throws { try Hokusai.initialize() }

    private func landscape() throws -> Hokusai {
        try Hokusai(data: loadFixtureData(named: "landscape-asym", ext: "jpg"))
    }

    /// Lowers a pipeline to a native image so tests can read size and pixels.
    private func lower(_ pipeline: Hokusai) throws -> NativeImage {
        try Evaluator.lower(pipeline.plan, context: EvaluationContext())
    }

    // MARK: - Ordering

    @Test func extractBeforeAndAfterResizeAreDifferentOperations() throws {
        let before = try lower(landscape().extract(x: 10, y: 10, width: 200, height: 100).resize(width: 100, fit: .fill))
        let after = try lower(landscape().resize(width: 160, fit: .fill).extract(x: 10, y: 10, width: 100, height: 60))
        #expect((before.width, before.height) == (100, 100))
        #expect((after.width, after.height) == (100, 60))
    }

    @Test func rotationAfterResizeKeepsWrittenOrder() throws {
        let image = try lower(landscape().resize(width: 160, height: 100, fit: .fill).rotate(by: 90))
        #expect((image.width, image.height) == (100, 160))
    }

    // MARK: - Resize

    @Test(arguments: [ResizeFit.cover, .contain, .fill, .inside, .outside])
    func everyFitProducesTheDocumentedSize(fit: ResizeFit) throws {
        let image = try lower(landscape().resize(width: 100, height: 100, fit: fit))
        switch fit {
        case .cover, .contain, .fill: #expect((image.width, image.height) == (100, 100))
        case .inside: #expect((image.width, image.height) == (100, 62))
        case .outside: #expect((image.width, image.height) == (160, 100))
        }
    }

    @Test func extremeAspectRatiosNeverRequestAnEmptyImage() throws {
        let image = try lower(landscape().resize(width: 1, fit: .inside))
        #expect(image.width == 1)
        #expect(image.height >= 1)
    }

    @Test(arguments: [ResizeKernel.nearest, .linear, .cubic, .mitchell, .lanczos2, .lanczos3])
    func standardKernelsResize(kernel: ResizeKernel) throws {
        let image = try lower(landscape().resize(width: 80, kernel: kernel))
        #expect(image.width == 80)
    }

    @Test(arguments: [ResizeKernel.mks2013, .mks2021])
    func magicKernelsAreGatedOnTheLibvipsVersion(kernel: ResizeKernel) throws {
        let supported = swift_vips_kernel_mks(kernel == .mks2013 ? 0 : 1) >= 0
        if supported {
            let actual1 = try lower(landscape().resize(width: 80, kernel: kernel)).width
            #expect(actual1 == 80)
        } else {
            expectHokusaiError({ try self.landscape().resize(width: 80, kernel: kernel) }) {
                if case .unsupported = $0 { true } else { false }
            }
        }
    }

    @Test func containPadsWithTheRequestedBackground() throws {
        let image = try lower(landscape().resize(width: 100, height: 100, fit: .contain, background: .white))
        let corner = try image.pixel(x: 0, y: 0)
        #expect(corner.prefix(3).allSatisfy { $0 > 250 }, "padding should be white, got \(corner)")
    }

    // MARK: - Extend

    @Test func extendTargetCanvasAnchorsEveryCompassPoint() throws {
        let anchors: [(Gravity, Int, Int)] = [
            (.northWest, 0, 0), (.north, 40, 0), (.northEast, 80, 0),
            (.west, 0, 40), (.center, 40, 40), (.east, 80, 40),
            (.southWest, 0, 80), (.south, 40, 80), (.southEast, 80, 80),
        ]
        for (anchor, x, y) in anchors {
            let image = try lower(
                landscape().resize(width: 40, height: 20, fit: .fill)
                    .extend(to: ImageSize(width: 120, height: 100), anchor: anchor, background: .white))
            #expect((image.width, image.height) == (120, 100))
            // The image is mostly black, so its top-left pixel is dark and the canvas is white.
            let inside = try image.pixel(x: x + 1, y: y + 1)
            #expect(inside.prefix(3).allSatisfy { $0 < 60 }, "\(anchor): expected image pixel at \(x),\(y), got \(inside)")
        }
    }

    @Test func extendCannotShrinkTheCanvas() throws {
        expectHokusaiError({ try self.lower(self.landscape().extend(to: ImageSize(width: 10, height: 10))) }) { $0.isInvalidOption }
    }

    @Test func edgeExtendAddsTheRequestedPadding() throws {
        let image = try lower(landscape().extend(top: 1, left: 2, bottom: 3, right: 4, mode: .copy))
        #expect((image.width, image.height) == (326, 204))
    }

    @Test func edgeExtendRejectsNegativeAndOversizedPadding() throws {
        #expect(throws: HokusaiError.self) { try self.landscape().extend(left: -1) }
        #expect(throws: HokusaiError.self) { try self.landscape().extend(left: maximumNativeCoordinate + 1) }
        // Each side is valid but the canvas is not.
        expectHokusaiError({ try self.lower(self.landscape().extend(left: maximumNativeCoordinate, right: maximumNativeCoordinate)) }) {
            $0.isInvalidOption
        }
    }

    @Test(arguments: [0, 1, 2, 3])
    func edgeExtensionModesProduceDifferentPadding(index: Int) throws {
        let source = try landscape().resize(width: 40, height: 20, fit: .fill)
        let modes: [ExtendMode] = [.background(.white), .copy, .repeat, .mirror]
        let padded = try lower(source.extend(left: 10, mode: modes[index]))
        let reference = try lower(source)
        #expect(padded.width == 50)

        let pad = try padded.pixel(x: 0, y: 10)
        switch index {
        case 0: #expect(pad.prefix(3).allSatisfy { $0 > 250 }, "background fill, got \(pad)")
        case 1: 
            let expected2 = try padded.pixel(x: 10, y: 10)
            #expect(pad == expected2, "copy repeats the edge pixel")
        case 2: 
            let expected3 = try reference.pixel(x: 30, y: 10)
            #expect(pad == expected3, "repeat tiles the image")
        default: 
            let expected4 = try reference.pixel(x: 9, y: 10)
            #expect(pad == expected4, "mirror reflects the image")
        }
    }

    @Test func transparentExtendKeepsTheAlphaChannel() throws {
        let png = try Hokusai(data: loadFixtureData(named: "rgba-alpha", ext: "png"))
        let image = try lower(png.extend(left: 3))
        #expect(image.hasAlpha)
        let pad = try image.pixel(x: 0, y: 0)
        #expect(pad.last == 0, "padding should be fully transparent, got \(pad)")
    }

    // MARK: - Rotate

    @Test(arguments: [90.0, 180, 270, -90, 450, 360, 0])
    func rightAngleRotationsKeepExpectedDimensions(degrees: Double) throws {
        let image = try lower(landscape().rotate(by: degrees))
        let turned = Int(degrees.truncatingRemainder(dividingBy: 360) + 360) % 360
        let swaps = turned == 90 || turned == 270
        #expect((image.width, image.height) == (swaps ? (200, 320) : (320, 200)))
    }

    @Test func rightAngleRotationMovesPixelsLosslessly() throws {
        let original = try lower(landscape())
        let rotated = try lower(landscape().rotate(by: 90))
        // 90° clockwise: the original's top-left pixel ends at the top-right.
        let actual5 = try rotated.pixel(x: rotated.width - 1, y: 0)
        let expected5 = try original.pixel(x: 0, y: 0)
        #expect(actual5 == expected5)
        let actual6 = try rotated.pixel(x: rotated.width - 1, y: original.width - 1)
        let expected6 = try original.pixel(x: original.width - 1, y: 0)
        #expect(actual6 == expected6)
    }

    @Test func hugeAngleDoesNotCrash() throws {
        let image = try lower(landscape().rotate(by: 1e300))
        #expect(image.width > 0)
    }

    @Test func arbitraryRotationFillsCornersWithTheBackground() throws {
        let image = try lower(landscape().rotate(by: 30, background: .white))
        #expect(image.width > 320)
        let corner = try image.pixel(x: 0, y: 0)
        #expect(corner.prefix(3).allSatisfy { $0 > 250 }, "corner should be white, got \(corner)")
    }

    @Test(arguments: Interpolation.allCases)
    func everyInterpolationRotates(interpolation: Interpolation) throws {
        let image = try lower(landscape().rotate(by: 15, interpolation: interpolation))
        #expect(image.width > 0 && image.height > 0)
    }

    // MARK: - Orientation, flip, flop

    @Test func autoOrientSwapsDimensionsAndClearsTheTag() throws {
        let data = try loadFixtureData(named: "orientation-6", ext: "jpg")
        let source = try Hokusai(data: data)
        let actual7 = try lower(source).width
        #expect(actual7 == 120)
        let oriented = try lower(source.autoOrient())
        #expect((oriented.width, oriented.height) == (80, 120))
        #expect(vips_image_get_orientation(oriented.pointer) == 1)
    }

    @Test func flipAndFlopMirrorOppositeAxes() throws {
        let original = try lower(landscape())
        let flipped = try lower(landscape().flip())
        let flopped = try lower(landscape().flop())
        let (w, h) = (original.width, original.height)
        // Sample inside the noise block so the three pixels differ.
        let actual8 = try flipped.pixel(x: 20, y: h - 1 - 60)
        let expected8 = try original.pixel(x: 20, y: 60)
        #expect(actual8 == expected8)
        let actual9 = try flopped.pixel(x: w - 1 - 20, y: 60)
        let expected9 = try original.pixel(x: 20, y: 60)
        #expect(actual9 == expected9)
    }

    @Test func orientationSensitiveOrderIsPreserved() throws {
        let data = try loadFixtureData(named: "orientation-6", ext: "jpg")
        // The EXIF tag survives `extend`, so it still turns the result.
        let orientFirst = try lower(Hokusai(data: data).autoOrient().extend(left: 10))
        let orientLast = try lower(Hokusai(data: data).extend(left: 10).autoOrient())
        #expect((orientFirst.width, orientFirst.height) == (90, 120))
        #expect((orientLast.width, orientLast.height) == (80, 130))
    }

    // MARK: - Affine

    @Test func identityAffineKeepsSizeAndPixels() throws {
        let original = try lower(landscape())
        let image = try lower(landscape().affine(.identity))
        #expect((image.width, image.height) == (original.width, original.height))
        let actual10 = try image.pixel(x: 50, y: 60)
        let expected10 = try original.pixel(x: 50, y: 60)
        #expect(actual10 == expected10)
    }

    @Test func affineScalesByTheMatrix() throws {
        let image = try lower(landscape().affine(AffineMatrix(a: 0.5, b: 0, c: 0, d: 0.5)))
        #expect((image.width, image.height) == (160, 100))
    }

    @Test func affineHonoursOutputArea() throws {
        let image = try lower(landscape().affine(.identity, outputArea: AffineArea(x: 10, y: 20, width: 30, height: 40)))
        #expect((image.width, image.height) == (30, 40))
    }

    @Test func affineShearFillsUncoveredAreaWithTheEdgeMode() throws {
        let shear = AffineMatrix(a: 1, b: 0.5, c: 0, d: 1)
        let white = try lower(landscape().affine(shear, edges: .background(.white)))
        let corner = try white.pixel(x: 0, y: white.height - 1)
        #expect(corner.prefix(3).allSatisfy { $0 > 250 }, "uncovered corner should be white, got \(corner)")
    }

    @Test func affineRejectsInvalidInput() throws {
        let nan = AffineMatrix(a: .nan, b: 0, c: 0, d: 1)
        expectHokusaiError({ try self.landscape().affine(nan) }) { $0.isInvalidOption }
        expectHokusaiError({ try self.landscape().affine(AffineMatrix(a: 1, b: 2, c: 2, d: 4)) }) { $0.isInvalidOption }
        expectHokusaiError({ try self.landscape().affine(.identity, inputOffset: AffineOffset(x: .infinity, y: 0)) }) { $0.isInvalidOption }
        expectHokusaiError({ try self.landscape().affine(.identity, outputArea: AffineArea(x: 0, y: 0, width: 0, height: 5)) }) { $0.isInvalidOption }
    }

    // MARK: - Immutability and independence

    @Test func branchingGeometryPipelinesStayIndependent() async throws {
        let base = try landscape().extract(x: 0, y: 0, width: 160, height: 100)
        async let rotated = base.rotate(by: 90).png().data()
        async let padded = base.extend(left: 10, right: 10).png().data()
        async let plain = base.png().data()
        let (a, b, c) = try await (rotated, padded, plain)
        #expect((a.info.width, a.info.height) == (100, 160))
        #expect(b.info.width == 180)
        #expect((c.info.width, c.info.height) == (160, 100))
    }

    @Test func pipelineValidationRejectsBadExtractOffsets() throws {
        #expect(throws: HokusaiError.self) { try self.landscape().extract(x: -1, y: 0, width: 10, height: 10) }
        #expect(throws: HokusaiError.self) { try self.landscape().extract(x: 0, y: -1, width: 10, height: 10) }
    }
}
