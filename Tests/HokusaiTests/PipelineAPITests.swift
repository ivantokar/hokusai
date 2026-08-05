import Foundation
import Testing
@testable import Hokusai
import HokusaiNIO
import NIOCore

@Suite struct PipelineAPITests {
    init() throws { try Hokusai.initialize() }

    @Test func dataPipelineBuildsSynchronouslyAndEncodesAsynchronously() async throws {
        let input = try loadFixtureData(named: "landscape-asym", ext: "jpg")
        let output = try await Hokusai(data: input)
            .autoOrient()
            .resize(width: 80, height: 80, fit: .cover, position: .attention)
            .webp(quality: 80)
            .data()

        #expect(output.info.format == .webp)
        #expect(output.info.width == 80)
        #expect(output.info.height == 80)
        #expect(output.info.size == output.data.count)
        #expect(!output.data.isEmpty)
    }

    @Test func copiedPipelinesCanBranchAndEvaluateConcurrently() async throws {
        let input = try loadFixtureData(named: "landscape-asym", ext: "jpg")
        let base = try Hokusai(data: input).autoOrient()

        async let small = base.resize(width: 64).jpeg().data()
        async let square = base.resize(width: 80, height: 80, fit: .cover).png().data()
        let (smallResult, squareResult) = try await (small, square)

        #expect(smallResult.info.width == 64)
        #expect(squareResult.info.width == 80)
        #expect(squareResult.info.height == 80)
    }

    @Test func outputValidationAndFileURLValidationAreExplicit() throws {
        let input = try loadFixtureData(named: "pixel", ext: "png")
        #expect(throws: HokusaiError.self) {
            try Hokusai(data: input).jpeg(quality: 101)
        }
        #expect(throws: HokusaiError.self) {
            try Hokusai(url: URL(string: "https://example.com/image.jpg")!)
        }
        #expect(throws: HokusaiError.self) {
            try Hokusai(data: input).resize(width: 0)
        }
    }

    @Test func writeInfersFormatFromURLWhenNoEncoderIsSelected() async throws {
        let input = try loadFixtureData(named: "pixel", ext: "png")
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let outputURL = directory.appendingPathComponent("hokusai-pipeline-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let info = try await Hokusai(data: input).write(to: outputURL)
        #expect(info.format == .png)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
    }

    @Test func typedCompositeLayerUsesPipelineInputs() async throws {
        let baseData = try loadFixtureData(named: "landscape-asym", ext: "jpg")
        let overlayData = try loadFixtureData(named: "pixel", ext: "png")
        let base = try Hokusai(data: baseData)
        let overlay = try Hokusai(data: overlayData).resize(width: 10, height: 10, fit: .fill)

        let output = try await base
            .composite([CompositeLayer(overlay, x: 4, y: 4, opacity: 0.5)])
            .png()
            .data()

        #expect(output.info.format == .png)
        #expect(output.info.width == 320)
        #expect(output.info.height == 200)
    }

    @Test func nativeBackedPipelineTransformsRemainChainable() async throws {
        let input = try loadFixtureData(named: "pixel", ext: "png")
        let output = try await Hokusai(data: input)
            .ensureAlpha()
            .blur(sigma: 1)
            .flatten(background: .white)
            .png()
            .data()
        #expect(output.info.format == .png)
        #expect(!output.data.isEmpty)
    }

    @Test func trimBuildsAnEncodablePipeline() async throws {
        let input = try loadFixtureData(named: "landscape-asym", ext: "jpg")
        let output = try await Hokusai(data: input).trim(threshold: 1).png().data()
        #expect(!output.data.isEmpty)
    }

    @Test func metadataDescribesThePipelineHeader() throws {
        let input = try loadFixtureData(named: "landscape-asym", ext: "jpg")
        let metadata = try Hokusai(data: input).metadata()

        #expect(metadata.width == 320)
        #expect(metadata.height == 200)
        #expect(metadata.channels == 3)
        #expect(metadata.space != nil)
    }

    @Test func colourTransformsProduceEncodablePipelines() async throws {
        let input = try loadFixtureData(named: "landscape-asym", ext: "jpg")
        let output = try await Hokusai(data: input)
            .grayscale()
            .tint(.init(red: 0.2, green: 0.4, blue: 0.8))
            .normalize()
            .convert(to: .sRGB)
            .png()
            .data()

        #expect(output.info.format == .png)
        #expect(output.info.width == 320)
    }

    @Test func nioBridgeCopiesInputAndOutputBytes() async throws {
        let input = try loadFixtureData(named: "pixel", ext: "png")
        var buffer = ByteBufferAllocator().buffer(capacity: input.count)
        buffer.writeBytes(input)

        let output = try await Hokusai(buffer: buffer).png().data()
        #expect(output.byteBuffer.readableBytes == output.data.count)
        #expect(output.byteBuffer.readableBytesView.elementsEqual(output.data))
    }

    @Test func pdfOutputProducesAValidSinglePageDocument() async throws {
        let input = try loadFixtureData(named: "landscape-asym", ext: "jpg")
        let output = try await Hokusai(data: input)
            .pdf(pageSize: .a4)
            .data()

        #expect(output.info.format == .pdf)
        #expect(output.data.starts(with: Data("%PDF-".utf8)))
        #expect(!output.data.isEmpty)
    }

    @Test func pdfWriteInfersFormatAndValidatesPageOptions() async throws {
        let input = try loadFixtureData(named: "pixel", ext: "png")
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let outputURL = directory.appendingPathComponent("hokusai-pipeline-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let info = try await Hokusai(data: input).write(to: outputURL)
        #expect(info.format == .pdf)
        #expect(try Data(contentsOf: outputURL).starts(with: Data("%PDF-".utf8)))
        #expect(throws: HokusaiError.self) {
            try Hokusai(data: input).pdf(dpi: 0)
        }
    }
}
