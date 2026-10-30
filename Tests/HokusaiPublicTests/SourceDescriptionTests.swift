import Foundation
import Hokusai
import Testing

/// What `metadata()` says about a source, and what encoder options do on every
/// sink: facts a caller reads or relies on without knowing how they are found.
@Suite struct SourceDescriptionTests {
    private func canEncode(_ format: ImageFormat) -> Bool {
        (try? Hokusai.capabilities().canEncode(format)) ?? false
    }

    private func landscape() throws -> Hokusai {
        try Hokusai(data: fixtureData(named: "landscape-asym", ext: "jpg"))
    }

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("hokusai-source-\(UUID().uuidString)-\(name)")
    }

    // MARK: - AVIF versus HEIF

    @Test func avifAndHEIFAreToldApartEvenThoughTheyShareAContainer() async throws {
        guard canEncode(.avif), canEncode(.heif), (try? Hokusai.capabilities().canEncode(HEIFCompression.hevc)) == true else { return }
        let avif = try await landscape().avif(quality: 50).data()
        let heif = try await landscape().heif(compression: .hevc, quality: 50).data()

        #expect(try await Hokusai(data: avif.data).metadata().format == .avif)
        #expect(try await Hokusai(data: heif.data).metadata().format == .heif)
    }

    @Test func theFormatComesFromTheBytesNotFromTheName() async throws {
        guard canEncode(.avif) else { return }
        let url = temporaryURL("really-avif.heic")
        defer { try? FileManager.default.removeItem(at: url) }
        let encoded = try await landscape().avif(quality: 50).data()
        try encoded.data.write(to: url)

        #expect(try await Hokusai(url: url).metadata().format == .avif)
    }

    // MARK: - ICC versus pixel interpretation

    /// A profile and a colour interpretation are independent facts: neither
    /// implies the other.
    @Test func iccPresenceDoesNotFollowFromThePixelInterpretation() async throws {
        let withProfile = try await Hokusai(data: fixtureData(named: "metadata-rich", ext: "jpg")).metadata()
        let withoutProfile = try await Hokusai(data: fixtureData(named: "landscape-asym", ext: "jpg")).metadata()

        #expect(withProfile.pixel.interpretation == .sRGB && withProfile.iccProfile != nil)
        #expect(withoutProfile.pixel.interpretation == .sRGB && withoutProfile.iccProfile == nil)
    }

    @Test func otherInterpretationsDescribeThemselvesWithoutAProfile() async throws {
        let cmyk = try await Hokusai(data: fixtureData(named: "cmyk", ext: "jpg")).metadata()
        #expect(cmyk.pixel.interpretation == .cmyk && cmyk.pixel.channels == 4)
        #expect(cmyk.iccProfile == nil, "a CMYK source is not assumed to carry a profile")

        let sixteen = try await Hokusai(data: fixtureData(named: "rgb16", ext: "png")).metadata()
        #expect(sixteen.pixel.interpretation == .rgb && sixteen.iccProfile == nil)
    }

    @Test func removingTheProfileDoesNotChangeTheInterpretation() async throws {
        let source = try Hokusai(data: fixtureData(named: "metadata-rich", ext: "jpg"))
        let output = try await source.jpeg().metadataPolicy(MetadataPolicy(icc: .remove)).data()
        let described = try await Hokusai(data: output.data).metadata()

        #expect(described.iccProfile == nil)
        #expect(described.pixel.interpretation == .sRGB)
    }

    // MARK: - Metadata blocks outlive their pipeline

    @Test func metadataBlocksStayValidAfterThePipelineIsGone() async throws {
        func read() async throws -> ImageMetadata {
            try await Hokusai(data: fixtureData(named: "metadata-rich", ext: "jpg")).metadata()
        }
        let first = try await read()
        let exif = try #require(first.exif), xmp = try #require(first.xmp)
        let icc = try #require(first.iccProfile), iptc = try #require(first.iptc)

        // Churn through other pipelines so freed native memory would be reused.
        for _ in 0..<50 { _ = try await landscape().resize(width: 40).jpeg().data() }

        let second = try await read()
        #expect(first.exif == exif && first.xmp == xmp && first.iccProfile == icc && first.iptc == iptc)
        #expect(second.exif == exif && second.xmp == xmp && second.iccProfile == icc && second.iptc == iptc)
        #expect(exif.starts(with: Data("Exif\0\0".utf8)))
    }

    // MARK: - AVIF options reach every sink

    @Test func avifEffortChangesTheOutputOnEverySink() async throws {
        guard canEncode(.avif) else { return }
        let urls = [temporaryURL("fast.avif"), temporaryURL("slow.avif")]
        defer { urls.forEach { try? FileManager.default.removeItem(at: $0) } }
        let fast = AVIFOptions(quality: 50, effort: 0), slow = AVIFOptions(quality: 50, effort: 9)

        let fastData = try await landscape().avif(options: fast).data()
        let slowData = try await landscape().avif(options: slow).data()
        _ = try await landscape().avif(options: fast).write(to: urls[0])
        _ = try await landscape().avif(options: slow).write(to: urls[1])

        #expect(fastData.data.count != slowData.data.count, "effort reaches the in-memory sink")
        let fastFile = try Data(contentsOf: urls[0]), slowFile = try Data(contentsOf: urls[1])
        #expect(fastFile.count != slowFile.count, "effort reaches the file sink")
        #expect(fastFile.count == fastData.data.count && slowFile.count == slowData.data.count, "both sinks apply the same settings")
    }

    @Test func avifLosslessReachesEverySink() async throws {
        guard canEncode(.avif) else { return }
        let url = temporaryURL("lossless.avif")
        defer { try? FileManager.default.removeItem(at: url) }
        let lossy = try await landscape().avif(options: AVIFOptions(quality: 30)).data()
        let lossless = try await landscape().avif(options: AVIFOptions(lossless: true)).data()
        _ = try await landscape().avif(options: AVIFOptions(lossless: true)).write(to: url)

        #expect(lossless.data.count > lossy.data.count)
        #expect(try Data(contentsOf: url).count == lossless.data.count)
    }
}
