import Foundation
import Hokusai
import Testing

/// The README's examples, run against committed fixtures. When an example in
/// `README.md` changes, change its test: each one names the section it covers.
/// Paths and variable names follow the README; only inputs are substituted.
@Suite struct ReadmeExampleTests {
    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("hokusai-readme-\(UUID().uuidString)-\(name)")
    }

    private func canEncode(_ format: ImageFormat) -> Bool {
        (try? Hokusai.capabilities().canEncode(format)) ?? false
    }

    /// "Quick start": resize with attention crop and write a WebP.
    @Test func quickStart() async throws {
        guard canEncode(.webp) else { return }
        let destination = temporaryURL("social-card.webp")
        defer { try? FileManager.default.removeItem(at: destination) }

        let output = try await Hokusai(url: fixtureURL(named: "orientation-6", ext: "jpg"))
            .autoOrient()
            .resize(width: 1200, height: 630, fit: .cover, position: .attention)
            .webp(quality: 82)
            .write(to: destination)

        #expect(output.width == 1200 && output.height == 630)
        #expect(output.format == .webp)
        let written = try Data(contentsOf: destination)
        #expect(output.byteCount == written.count)
    }

    /// "Inputs and outputs": the same pipeline from bytes and from a file.
    @Test func dataAndFileInputsAndOutputs() async throws {
        let uploadData = try fixtureData(named: "landscape-asym", ext: "jpg")
        let photo = try fixtureURL(named: "landscape-asym", ext: "jpg")
        let destination = temporaryURL("output.png")
        defer { try? FileManager.default.removeItem(at: destination) }

        let fromData = try Hokusai(data: uploadData)
        let fromFile = try Hokusai(url: photo)

        let jpeg = try await fromData.jpeg(quality: 85).data()
        let png = try await fromData.png(compressionLevel: 6).data()
        let info = try await fromFile.write(to: destination)

        #expect(jpeg.info.format == .jpeg && png.info.format == .png)
        #expect(info.format == .png)          // the extension picks the format
        #expect(jpeg.info.width == png.info.width && jpeg.info.height == png.info.height)
    }

    /// "Streaming output": chunks join to what `data()` returns and the info totals them.
    @Test func streamingOutput() async throws {
        guard canEncode(.webp) else { return }
        let image = try Hokusai(data: fixtureData(named: "landscape-asym", ext: "jpg"))
        var received = Data()
        let info = try await image
            .webp(quality: 82)
            .writeChunks(chunkSize: 64 * 1024) { chunk in
                received.append(chunk)
            }
        let direct = try await image.webp(quality: 82).data()
        #expect(received == direct.data)
        #expect(info.byteCount == received.count)
    }

    /// "Metadata policy": every spelling in the README is accepted and applies.
    @Test func metadataPolicySpellings() async throws {
        let image = try Hokusai(data: fixtureData(named: "metadata-rich", ext: "jpg"))
        let byPolicy = [
            try await image.jpeg().data(),
            try await image.jpeg().metadataPolicy(.preserveAll).data(),
            try await image.png().metadataPolicy(MetadataPolicy(icc: .remove, density: .remove)).data(),
        ]
        #expect(byPolicy.allSatisfy { $0.info.byteCount > 0 })

        if canEncode(.webp) {
            let webp = try await image.webp().metadataPolicy(.removeAll).data()
            let metadata = try await Hokusai(data: webp.data).metadata()
            #expect(metadata.exif == nil && metadata.xmp == nil && metadata.iptc == nil)
        }
    }

    /// "Metadata": the fields the README lists exist and mean what it says.
    @Test func metadataFields() async throws {
        let photoURL = try fixtureURL(named: "orientation-6", ext: "jpg")
        let metadata = try await Hokusai(url: photoURL).metadata()

        #expect(metadata.format == .jpeg)
        #expect(metadata.orientation?.swapsDimensions == true)       // orientation 6
        #expect(metadata.orientedSize.width == metadata.height && metadata.orientedSize.height == metadata.width)
        #expect(metadata.pixel.interpretation == .sRGB)
        let fileSize = try Data(contentsOf: photoURL).count
        #expect(metadata.sourceByteSize == fileSize)
    }

    /// "Input options": the options literal from the README, plus the failure it promises.
    @Test func inputOptions() async throws {
        let upload = try fixtureData(named: "multipage", ext: "tif")
        let image = try Hokusai(
            data: upload,
            options: .init(
                failOn: .truncated,
                page: 1,
                limits: .init(maxBytes: 20_000_000, maxPixels: 50_000_000)
            )
        )
        let output = try await image.png().data()
        #expect(output.info.width > 0)

        let truncated = try Hokusai(data: fixtureData(named: "truncated", ext: "jpg"), options: .init(failOn: .truncated))
        do {
            _ = try await truncated.png().data()
            Issue.record("a truncated file must fail when failOn is .truncated")
        } catch HokusaiError.decode {
        } catch {
            Issue.record("expected decode, got \(error)")
        }
    }

    /// "Compositing and text": base, logo, text overlay, flatten and standalone text.
    @Test func compositingAndText() async throws {
        guard (try? Hokusai.capabilities().textRendering) == true else { return }
        let base = try Hokusai(url: fixtureURL(named: "landscape-asym", ext: "jpg"))
        let logo = try Hokusai(url: fixtureURL(named: "rgba-alpha", ext: "png"))

        let label = TextStyle(
            font: "sans Bold", fontSize: 48, color: .white,
            stroke: TextStroke(color: Color(red: 0, green: 0, blue: 0), width: 2))

        let image = try base
            .resize(width: 1200, height: 800, fit: .cover)
            .composite([CompositeLayer(logo, placement: .gravity(.northWest, offsetX: 32, offsetY: 32), opacity: 0.8)])
            .drawText("Hello, Hokusai", placement: .gravity(.southWest, offsetX: 80, offsetY: 40), style: label)
            .flatten(background: .white)

        let result = try await image.png().data()
        #expect(result.info.width == 1200 && result.info.height == 800)

        let badge = try await Hokusai.text("SALE", layout: .fit(width: 300, height: 120)).png().data()
        #expect(badge.info.format == .png && badge.info.width > 0)
    }

    /// "PDF output": a raster document on A4 with margins and metadata.
    @Test func pdfOutput() async throws {
        guard canEncode(.pdf) else { return }
        let destination = temporaryURL("report.pdf")
        defer { try? FileManager.default.removeItem(at: destination) }

        let info = try await Hokusai(url: fixtureURL(named: "landscape-asym", ext: "jpg"))
            .resize(width: 1240)
            .pdf(
                pageSize: .a4(),
                margins: .all(36),
                background: .white,
                metadata: PDFDocumentMetadata(title: "Site photo")
            )
            .write(to: destination)

        let pageWidth = try #require(info.pdf?.pageWidth)
        #expect(abs(pageWidth - 595.276) < 0.01)
        let document = try Data(contentsOf: destination)
        #expect(document.starts(with: Data("%PDF-".utf8)))
    }

    /// "Runtime configuration" cannot run here, because configuration freezes at
    /// first use in this process; `RuntimeProcessTests` runs it in a fresh one.
    /// Keeping the call compiled still catches a renamed or removed option.
    func runtimeConfigurationCompiles() throws {
        try Hokusai.configure(.init(
            maxConcurrentEvaluations: .fixed(4),
            maxQueuedEvaluations: 64,
            vipsConcurrency: .fixed(2),
            blockUntrustedOperations: true
        ))
    }

    /// "Capabilities and status".
    @Test func capabilitiesAndStatus() throws {
        let capabilities = try Hokusai.capabilities()
        #expect(capabilities.canEncode(.png))
        let status = Hokusai.runtimeStatus
        #expect(status.queuedEvaluations >= 0 && status.activeEvaluations >= 0)
    }

    /// "Errors": the exhaustive switch in the README covers every case.
    @Test func errorHandlingCoversEveryCase() async throws {
        let image = try Hokusai(data: Data(repeating: 0x42, count: 64))
        var classified = false
        do {
            _ = try await image.webp().data()
        } catch is CancellationError {
        } catch let error as HokusaiError {
            switch error {
            case .invalidInput, .invalidOption: break
            case .unsupported: break
            case .decode, .transform, .encode: classified = true
            case .io: break
            case .resource: break
            case .runtime: break
            }
        }
        #expect(classified)
    }
}
