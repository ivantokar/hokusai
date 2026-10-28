import Foundation
import Testing
@testable import Hokusai

/// Output metadata policy (#24). Outputs are read back through `metadata()`,
/// so every assertion is about what the encoded bytes actually carry.
@Suite struct MetadataPolicyTests {
    init() throws { try Hokusai.initialize() }

    // MARK: - Helpers

    /// EXIF with orientation 6 and a description, XMP, IPTC, an ICC profile, 72 DPI.
    private func rich() throws -> Hokusai {
        try Hokusai(data: loadFixtureData(named: "metadata-rich", ext: "jpg"))
    }

    /// 120×80 stored, orientation 6.
    private func rotated() throws -> Hokusai {
        try Hokusai(data: loadFixtureData(named: "orientation-6", ext: "jpg"))
    }

    private func read(_ output: Output) async throws -> ImageMetadata {
        try await Hokusai(data: output.data).metadata()
    }

    private func contains(_ data: Data?, _ text: String) -> Bool {
        data?.range(of: Data(text.utf8)) != nil
    }

    private var avifAvailable: Bool { (try? Hokusai.capabilities().canEncode(.avif)) ?? false }

    // MARK: - The policy value

    @Test func defaultsAreRenderingSafeAndPrivate() {
        let policy = MetadataPolicy.default
        #expect(policy == MetadataPolicy())
        #expect([policy.exif, policy.xmp, policy.iptc, policy.other].allSatisfy { $0 == .remove })
        #expect([policy.icc, policy.orientation, policy.density].allSatisfy { $0 == .preserve })

        func actions(_ policy: MetadataPolicy) -> [MetadataPolicy.Action] {
            [policy.exif, policy.icc, policy.xmp, policy.iptc, policy.other, policy.orientation, policy.density]
        }
        #expect(actions(.preserveAll).allSatisfy { $0 == .preserve })
        #expect(actions(.removeAll).allSatisfy { $0 == .remove })
    }

    @Test func thePolicyIsTerminalConfigurationNotAnImageOperation() async throws {
        let image = try rich().resize(width: 8)
        let configured = try image.jpeg().metadataPolicy(.removeAll)
        #expect(configured.plan.linearized.operations.map(\.name) == image.plan.linearized.operations.map(\.name))
        #expect(configured.terminal.metadataPolicy == .removeAll)

        // The last call wins, and the source's own metadata is unaffected.
        let reconfigured = configured.metadataPolicy(.preserveAll).metadataPolicy(.default)
        #expect(reconfigured.terminal.metadataPolicy == .default)
        let before = try await image.metadata()
        let after = try await configured.metadata()
        #expect(before == after)
    }

    // MARK: - Native lowering

    @Test func familiesLowerToNativeKeepFlags() throws {
        let rich = try NativeImage.open(data: loadFixtureData(named: "metadata-rich", ext: "jpg"))
        let plain = try NativeImage.open(data: loadFixtureData(named: "pixel", ext: "png"))
        let exif = Int32(1), xmp = Int32(2), iptc = Int32(4), icc = Int32(8), other = Int32(16)

        // Default: ICC, plus a minimal EXIF only because an orientation exists to carry.
        #expect(try MetadataPolicy.default.lowered(for: rich, format: .jpeg).keep == icc | exif)
        #expect(try MetadataPolicy.default.lowered(for: plain, format: .png).keep == icc)

        #expect(try MetadataPolicy.preserveAll.lowered(for: rich, format: .jpeg).keep == exif | xmp | iptc | icc | other)
        #expect(try MetadataPolicy.removeAll.lowered(for: rich, format: .jpeg).keep == 0)
        #expect(try MetadataPolicy(exif: .remove, icc: .remove, xmp: .preserve, orientation: .remove)
            .lowered(for: rich, format: .jpeg).keep == xmp)
        #expect(try MetadataPolicy(icc: .remove, iptc: .preserve, orientation: .remove)
            .lowered(for: rich, format: .jpeg).keep == iptc)
    }

    @Test func headerEditsNeverChangePixelsOrTheSource() throws {
        let source = try NativeImage.open(data: loadFixtureData(named: "metadata-rich", ext: "jpg"))
        let (edited, _) = try MetadataPolicy.removeAll.lowered(for: source, format: .jpeg)

        #expect((edited.width, edited.height) == (source.width, source.height))
        // Edits happen on a private copy; the opened source keeps its fields.
        #expect(source.hasMetadataField("orientation"))
        #expect(source.hasMetadataField("exif-ifd0-ImageDescription"))
        #expect(!edited.hasMetadataField("orientation"))
    }

    // MARK: - JPEG: every family

    @Test func theDefaultKeepsTheProfileOrientationAndDensityOnly() async throws {
        let output = try await rich().jpeg().data()
        let metadata = try await read(output)

        #expect(metadata.iccProfile != nil)
        #expect(metadata.orientation == .right)
        let density = try #require(metadata.density)
        #expect(abs(density.horizontal - 72) < 0.5)

        #expect(metadata.xmp == nil && metadata.iptc == nil)
        // A minimal EXIF block carries the orientation; the description is gone.
        #expect(metadata.exif != nil)
        #expect(!contains(metadata.exif, "hokusai"))
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

    @Test func removingDensityDropsTheSourceResolution() async throws {
        // density-cm.tif records 300 DPI, which must not reach the output.
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

    @Test func removingOrientationDeletesTheTagWithoutRotating() async throws {
        let kept = try await read(rotated().jpeg().data())
        #expect(kept.orientation == .right)
        #expect((kept.width, kept.height) == (120, 80), "keeping the tag does not rotate either")

        let removed = try await read(rotated().jpeg().metadataPolicy(MetadataPolicy(orientation: .remove)).data())
        #expect(removed.orientation == nil)
        #expect(removed.exif == nil, "with EXIF removed too, nothing is left to hold it")
        #expect((removed.width, removed.height) == (120, 80))
    }

    @Test func removingOrientationFromFullEXIFWritesTheNeutralValue() async throws {
        // EXIF cannot omit the entry, so the tag reads "up" rather than missing.
        let metadata = try await read(
            rotated().jpeg().metadataPolicy(MetadataPolicy(exif: .preserve, orientation: .remove)).data())
        #expect(metadata.orientation == .up)
        #expect(metadata.orientedSize == ImageSize(width: 120, height: 80))
    }

    @Test func autoOrientApplyingTheTagLeavesNothingToPreserve() async throws {
        let output = try await rotated().autoOrient().jpeg().data()
        let metadata = try await read(output)
        #expect((metadata.width, metadata.height) == (80, 120))
        #expect(metadata.orientation == nil || metadata.orientation == .up)
    }

    @Test func densityCanBeKeptOrReset() async throws {
        let kept = try await read(rich().jpeg().data())
        #expect(kept.density != nil)

        let reset = try await read(rich().jpeg().metadataPolicy(MetadataPolicy(density: .remove)).data())
        #expect(reset.density == nil)
        #expect(reset.iccProfile != nil && reset.orientation == .right, "only density changed")

        let png = try await read(rich().png().metadataPolicy(MetadataPolicy(density: .remove)).data())
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

    @Test func webPHasNoDensityToKeepOrRemove() async throws {
        let metadata = try await read(rich().webp().metadataPolicy(.preserveAll).data())
        #expect(metadata.density == nil)
    }

    @Test(.enabled(if: (try? Hokusai.capabilities().canEncode(.avif)) ?? false, "AVIF not available in this libvips build"))
    func avifKeepsOrientationAsARotationOrAnEXIFTag() async throws {
        // How AVIF carries orientation depends on the libvips build. libvips
        // 8.18 writes a container rotation, which readers apply, so the sides
        // read back swapped. The 8.16 baseline keeps only the EXIF tag, which
        // AVIF readers ignore. Either way the tag is not applied by Hokusai.
        let kept = try await read(rotated().avif(quality: 50, effort: 2).data())
        let rotatedByContainer = (kept.width, kept.height) == (80, 120)
        #expect(rotatedByContainer || kept.exif != nil, "orientation survives in one of the two forms")
        #expect(kept.orientation == nil, "readers never report the tag for AVIF")

        let removed = try await read(rotated().avif(quality: 50, effort: 2).metadataPolicy(MetadataPolicy(orientation: .remove)).data())
        #expect((removed.width, removed.height) == (120, 80))

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

    // MARK: - Pipelines without metadata

    @Test func imagesWithoutMetadataStillEncodeUnderEveryPolicy() async throws {
        let source = try Hokusai(data: loadFixtureData(named: "pixel", ext: "png"))
        for policy in [MetadataPolicy.default, .preserveAll, .removeAll] {
            let metadata = try await read(source.png().metadataPolicy(policy).data())
            // Keeping EXIF in full makes libvips write one with the neutral "up".
            #expect(metadata.orientation == nil || metadata.orientation == .up)
            #expect((metadata.width, metadata.height) == (1, 1))
        }
    }
}
