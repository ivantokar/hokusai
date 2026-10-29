import Foundation
import Hokusai
import Testing

/// Source metadata and output metadata policy (#24, #43), black box. Outputs
/// are read back through `metadata()`, so each assertion is about what the
/// encoded bytes actually carry.
@Suite struct MetadataSemanticsTests {
    /// EXIF with orientation 6 and a description, XMP, IPTC, an ICC profile, 72 DPI.
    private func rich() throws -> Hokusai {
        try Hokusai(data: fixtureData(named: "metadata-rich", ext: "jpg"))
    }

    /// 120×80 stored, orientation 6.
    private func rotated() throws -> Hokusai {
        try Hokusai(data: fixtureData(named: "orientation-6", ext: "jpg"))
    }

    private func read(_ output: Output) async throws -> ImageMetadata {
        try await Hokusai(data: output.data).metadata()
    }

    private func contains(_ data: Data?, _ text: String) -> Bool {
        data?.range(of: Data(text.utf8)) != nil
    }

    // MARK: - The policy value

    @Test func defaultsAreRenderingSafeAndPrivate() {
        let policy = MetadataPolicy.default
        #expect(policy == MetadataPolicy())
        #expect([policy.exif, policy.xmp, policy.iptc, policy.other].allSatisfy { $0 == .remove })
        #expect([policy.icc, policy.orientation, policy.density].allSatisfy { $0 == .preserve })
    }

    // MARK: - Source metadata

    @Test func sourceMetadataDescribesTheFileNotTheOutputPolicy() async throws {
        let image = try rich()
        let before = try await image.metadata()
        let configured = try image.resize(width: 8).jpeg().metadataPolicy(.removeAll)
        #expect(try await configured.metadata() == before, "downstream steps and policy do not touch metadata()")

        #expect(before.format == .jpeg)
        #expect(contains(before.exif, "hokusai") && contains(before.xmp, "hokusai"))
        #expect(contains(before.iptc, "hokusai fixture"))
        #expect(before.iccProfile != nil)
        let fileSize = try fixtureData(named: "metadata-rich", ext: "jpg").count
        #expect(before.sourceByteSize == fileSize)
    }

    @Test func aMultiPageFileIsNotAnAnimation() async throws {
        let tiff = try await Hokusai(url: fixtureURL(named: "multipage", ext: "tif")).metadata()
        #expect(tiff.pages.count == 3)
        #expect(!tiff.isAnimated && tiff.animation == nil)
    }

    @Test func aSinglePageFileHasOnePage() async throws {
        let metadata = try await rich().metadata()
        #expect(metadata.pages.count == 1 && !metadata.isAnimated)
    }

    // MARK: - JPEG: every family

    @Test func theDefaultKeepsTheProfileOrientationAndDensityOnly() async throws {
        let metadata = try await read(rich().jpeg().data())

        #expect(metadata.iccProfile != nil)
        #expect(metadata.orientation == .right)
        let density = try #require(metadata.density)
        #expect(abs(density.horizontal - 72) < 0.5)

        #expect(metadata.xmp == nil && metadata.iptc == nil)
        #expect(!contains(metadata.exif, "hokusai"), "the description is gone")
    }

    @Test func preserveAllKeepsEveryFamily() async throws {
        let metadata = try await read(rich().jpeg().metadataPolicy(.preserveAll).data())

        #expect(contains(metadata.exif, "hokusai"))
        #expect(contains(metadata.xmp, "<dc:creator>hokusai</dc:creator>"))
        #expect(contains(metadata.iptc, "hokusai fixture"))
        #expect(metadata.iccProfile != nil)
        #expect(metadata.orientation == .right)
        #expect(metadata.density != nil)
    }

    @Test func removeAllRemovesEverythingButLeavesPixelsAlone() async throws {
        let metadata = try await read(rotated().jpeg().metadataPolicy(.removeAll).data())

        #expect(metadata.exif == nil && metadata.xmp == nil && metadata.iptc == nil && metadata.iccProfile == nil)
        #expect(metadata.orientation == nil)
        #expect((metadata.width, metadata.height) == (120, 80), "the pixels are not rotated")
    }

    @Test func eachFamilyIsControlledOnItsOwn() async throws {
        let source = try rich()

        let exifOnly = try await read(source.jpeg().metadataPolicy(MetadataPolicy(exif: .preserve)).data())
        #expect(contains(exifOnly.exif, "hokusai"))
        #expect(exifOnly.xmp == nil && exifOnly.iptc == nil && exifOnly.iccProfile != nil)

        let xmpOnly = try await read(source.jpeg().metadataPolicy(MetadataPolicy(xmp: .preserve)).data())
        #expect(contains(xmpOnly.xmp, "hokusai"))
        #expect(!contains(xmpOnly.exif, "hokusai") && xmpOnly.iptc == nil)

        let iptcOnly = try await read(source.jpeg().metadataPolicy(MetadataPolicy(iptc: .preserve)).data())
        #expect(contains(iptcOnly.iptc, "hokusai fixture"))
        #expect(iptcOnly.xmp == nil && !contains(iptcOnly.exif, "hokusai"))

        let noProfile = try await read(source.jpeg().metadataPolicy(MetadataPolicy(icc: .remove)).data())
        #expect(noProfile.iccProfile == nil)
        #expect(noProfile.orientation == .right && noProfile.density != nil, "the other defaults still hold")
    }

    // MARK: - Orientation and density

    @Test func keepingOrCarryingTheTagNeverRotatesPixels() async throws {
        let kept = try await read(rotated().jpeg().data())
        #expect(kept.orientation == .right)
        #expect((kept.width, kept.height) == (120, 80))

        let removed = try await read(rotated().jpeg().metadataPolicy(MetadataPolicy(orientation: .remove)).data())
        #expect(removed.orientation == nil)
        #expect((removed.width, removed.height) == (120, 80))
    }

    @Test func removingOrientationFromFullEXIFWritesTheNeutralValue() async throws {
        let metadata = try await read(
            rotated().jpeg().metadataPolicy(MetadataPolicy(exif: .preserve, orientation: .remove)).data())
        #expect(metadata.orientation == .up)
        #expect(metadata.orientedSize == ImageSize(width: 120, height: 80))
    }

    @Test func autoOrientApplyingTheTagLeavesNothingToPreserve() async throws {
        let metadata = try await read(rotated().autoOrient().jpeg().data())
        #expect((metadata.width, metadata.height) == (80, 120))
        #expect(metadata.orientation == nil || metadata.orientation == .up)
    }

    @Test func densityCanBeKeptOrDropped() async throws {
        // density-cm.tif records 300 DPI.
        let source = try Hokusai(url: fixtureURL(named: "density-cm", ext: "tif"))
        let carried = try await read(source.jpeg().data())
        #expect(abs((carried.density?.horizontal ?? 0) - 300) < 1)

        for policy in [MetadataPolicy(density: .remove), .removeAll] {
            let dropped = try await read(source.jpeg().metadataPolicy(policy).data())
            #expect(dropped.density == nil || abs(dropped.density!.horizontal - 300) > 1)
        }
        let png = try await read(source.png().metadataPolicy(MetadataPolicy(density: .remove)).data())
        #expect(png.density == nil)
    }

    // MARK: - Other formats

    @Test func pngAndWebPFollowThePolicyWhereTheFormatAllows() async throws {
        for make in [{ (image: Hokusai) in try image.png() }, { (image: Hokusai) in try image.webp() }] {
            let kept = try await read(make(rich()).data())
            #expect(kept.iccProfile != nil && kept.orientation == .right)
            #expect(kept.xmp == nil && !contains(kept.exif, "hokusai"))

            let all = try await read(make(rich()).metadataPolicy(.preserveAll).data())
            #expect(contains(all.exif, "hokusai") && contains(all.xmp, "hokusai"))
            #expect(all.iptc == nil, "neither format has an IPTC block")

            let none = try await read(make(rich()).metadataPolicy(.removeAll).data())
            #expect(none.exif == nil && none.xmp == nil && none.iccProfile == nil && none.orientation == nil)
        }
    }

    @Test(.enabled(if: (try? Hokusai.capabilities().canEncode(.avif)) ?? false, "AVIF not available in this libvips build"))
    func avifFollowsThePolicy() async throws {
        let all = try await read(rich().avif(quality: 50, effort: 2).metadataPolicy(.preserveAll).data())
        #expect(contains(all.exif, "hokusai") && all.xmp != nil && all.iccProfile != nil)

        let none = try await read(rich().avif(quality: 50, effort: 2).metadataPolicy(.removeAll).data())
        #expect(none.exif == nil && none.xmp == nil && none.iccProfile == nil)
    }

    // MARK: - Sinks

    @Test(arguments: [MetadataPolicy.default, .preserveAll, .removeAll, MetadataPolicy(exif: .preserve, icc: .remove, density: .remove)])
    func dataAndFileOutputsAgreeForEveryPolicy(policy: MetadataPolicy) async throws {
        for make in [{ (image: Hokusai) in try image.jpeg() }, { (image: Hokusai) in try image.png() }, { (image: Hokusai) in try image.webp() }] {
            let pipeline = try make(rich()).metadataPolicy(policy)
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hokusai-policy-\(UUID().uuidString).img")
            defer { try? FileManager.default.removeItem(at: url) }

            let memory = try await pipeline.data()
            try await pipeline.write(to: url)
            let file = try Data(contentsOf: url)
            #expect(memory.data == file)
        }
    }

    @Test func imagesWithoutMetadataStillEncodeUnderEveryPolicy() async throws {
        let source = try Hokusai(data: fixtureData(named: "pixel", ext: "png"))
        for policy in [MetadataPolicy.default, .preserveAll, .removeAll] {
            let metadata = try await read(source.png().metadataPolicy(policy).data())
            #expect(metadata.orientation == nil || metadata.orientation == .up)
            #expect((metadata.width, metadata.height) == (1, 1))
        }
    }
}
