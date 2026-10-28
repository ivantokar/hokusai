import ArgumentParser
import Foundation
import Hokusai
import Testing
@testable import HokusaiCommandLine

/// Strict parsing: an unknown or out-of-range value fails instead of becoming a default.
@Suite struct ArgumentParsingTests {
    private let base = ["--input", "in.jpg", "--output", "out.png"]

    private func rejects<C: ParsableCommand>(_ type: C.Type, _ arguments: [String], sourceLocation: SourceLocation = #_sourceLocation) {
        do {
            _ = try C.parse(arguments)
            Issue.record("expected \(arguments.joined(separator: " ")) to be rejected", sourceLocation: sourceLocation)
        } catch {}
    }

    // MARK: - Words

    @Test func unknownFitKernelAndAlignmentAreRejected() {
        rejects(ResizeCommand.self, base + ["--width", "10", "--fit", "bogus"])
        rejects(ResizeCommand.self, base + ["--width", "10", "--kernel", "bicubic-ish"])
        rejects(TextCommand.self, base + ["--text", "hi", "--align", "middle"])
        rejects(ThumbnailCommand.self, base + ["--width", "10", "--height", "10", "--crop", "smart"])
    }

    @Test func documentedWordsAreAcceptedInAnyCase() throws {
        let resize = try ResizeCommand.parse(base + ["--width", "10", "--fit", "COVER", "--kernel", "Mitchell"])
        #expect(resize.fit == .cover && resize.kernel == .mitchell)
        #expect(try ResizeCommand.parse(base + ["--width", "10"]).fit == .inside)
        #expect(try ResizeCommand.parse(base + ["--width", "10"]).kernel == .lanczos3)
        #expect(try TextCommand.parse(base + ["--text", "hi", "--align", "Right"]).typography.align == .right)
    }

    @Test func everyKernelAndFitMapsToItsPublicCounterpart() {
        let kernels: [(ResizeKernelArgument, ResizeKernel)] = [
            (.nearest, .nearest), (.linear, .linear), (.cubic, .cubic), (.mitchell, .mitchell),
            (.lanczos2, .lanczos2), (.lanczos3, .lanczos3), (.mks2013, .mks2013), (.mks2021, .mks2021),
        ]
        #expect(kernels.allSatisfy { $0.0.kernel == $0.1 })
        #expect(kernels.count == ResizeKernelArgument.allCases.count)
        #expect(ResizeFitArgument.allCases.map(\.fit) == [.inside, .outside, .fill, .cover, .contain])
    }

    @Test func cropWordsIncludeTheDocumentedAliases() throws {
        for (word, position): (String, ResizePosition?) in [
            ("none", nil), ("centre", .center), ("center", .center), ("CENTRE", .center),
            ("attention", .attention), ("entropy", .entropy),
        ] {
            #expect(CropStrategyArgument(argument: word)?.position == position, "\(word)")
        }
        #expect(CropStrategyArgument(argument: "smart") == nil)
        #expect(CropStrategyArgument(argument: "") == nil)
    }

    // MARK: - Colours

    @Test func coloursAreParsedAsByteComponents() throws {
        #expect(try ColorParser.parse("255,0,0") == Color(red: 1, green: 0, blue: 0))
        #expect(try ColorParser.parse(" 0, 0, 255, 0 ") == Color(red: 0, green: 0, blue: 1, opacity: 0))
        #expect(try ColorParser.parse("255,255,255,255") == .white)
    }

    @Test func malformedNonFiniteAndOutOfRangeColoursAreRejectedNotClamped() {
        for bad in ["", "1,2", "1,2,3,4,5", "a,b,c", "300,0,0", "-1,0,0", "0,0,0,256", "nan,0,0", "inf,0,0", "0,0,0,-0.5", "1,,3"] {
            #expect(throws: (any Error).self, "\(bad)") { try ColorParser.parse(bad) }
        }
        rejects(RotateCommand.self, base + ["--angle", "10", "--background", "999,0,0"])
        rejects(TextCommand.self, base + ["--text", "hi", "--color", "1,2"])
    }

    // MARK: - Formats

    @Test func formatsAndExtensionsAcceptTheDocumentedAliases() {
        #expect(OutputFormatArgument(argument: "jpg") == .jpeg)
        #expect(OutputFormatArgument(argument: "TIF") == .tiff)
        #expect(OutputFormatArgument(argument: "heic") == .heif)
        #expect(OutputFormatArgument(pathExtensionOf: "/a/b/photo.JPG") == .jpeg)
        #expect(OutputFormatArgument(pathExtensionOf: "photo") == nil)
        #expect(OutputFormatArgument(pathExtensionOf: "photo.unknown") == nil)
        // SVG is input only, and never a selectable output.
        #expect(OutputFormatArgument(argument: "svg") == nil)
    }

    @Test func theResolverFollowsTheExtensionWhenNoFormatIsGiven() throws {
        #expect(try OutputFormatResolver.resolve(explicit: nil, outputPath: "out.webp") == .webp)
        #expect(try OutputFormatResolver.resolve(explicit: .jpeg, outputPath: "out.jpg") == .jpeg)
        #expect(try OutputFormatResolver.resolve(explicit: .png, outputPath: "no-extension") == .png)
        #expect(try OutputFormatResolver.resolve(explicit: .png, outputPath: "out.unknown") == .png)
    }

    @Test func theResolverRejectsConflictsMissingFormatsAndSVG() {
        #expect(throws: (any Error).self) { try OutputFormatResolver.resolve(explicit: .webp, outputPath: "photo.jpg") }
        #expect(throws: (any Error).self) { try OutputFormatResolver.resolve(explicit: nil, outputPath: "noextension") }
        #expect(throws: (any Error).self) { try OutputFormatResolver.resolve(explicit: nil, outputPath: "icon.svg") }
        #expect(throws: (any Error).self) { try OutputFormatResolver.resolve(explicit: .png, outputPath: "icon.svg") }
        rejects(ConvertCommand.self, ["--input", "in.jpg", "--output", "out.jpg", "--format", "webp"])
        rejects(ConvertCommand.self, ["--input", "in.jpg", "--output", "out.jpg", "--format", "svg"])
    }

    // MARK: - Shape of the command line

    @Test func resizeNeedsAtLeastOneDimensionButLeavesRangesToTheLibrary() throws {
        rejects(ResizeCommand.self, base)
        // Ranges are Hokusai's to validate: these parse, and fail when the pipeline is built.
        _ = try ResizeCommand.parse(base + ["--width", "0"])
        _ = try ThumbnailCommand.parse(base + ["--width=-3"])
    }

    @Test func thumbnailCropNeedsAHeight() throws {
        rejects(ThumbnailCommand.self, base + ["--width", "400", "--crop", "attention"])
        let command = try ThumbnailCommand.parse(base + ["--width", "400", "--height", "300", "--crop", "attention", "--no-rotate"])
        #expect(command.plan == ThumbnailPlan(width: 400, height: 300, crop: .attention, autoOrient: false))
        #expect(try ThumbnailCommand.parse(base + ["--width", "400"]).plan.autoOrient)
    }

    @Test func textOptionsThatWouldBeSilentlyDroppedAreRejected() {
        let text = base + ["--text", "hi"]
        rejects(TextCommand.self, text + ["--text-height", "40"])
        rejects(TextCommand.self, text + ["--stroke-color", "1,2,3"])
        rejects(TextCommand.self, text + ["--shadow-offset-x", "2"])
        rejects(TextCommand.self, text + ["--shadow-color", "1,2,3"])
        rejects(TextCommand.self, text + ["--shadow-offset-x", "2", "--shadow-offset-y", "2", "--shadow-opacity", "1.5"])
        rejects(TextCommand.self, text + ["--shadow-offset-x", "2", "--shadow-offset-y", "2", "--shadow-opacity", "nan"])
    }

    @Test func textStyleKeepsFamilyAndFontFileApart() throws {
        let family = try TextCommand.parse(base + ["--text", "hi", "--font", "Serif Bold"]).typography.style
        #expect(family.font == "Serif Bold" && family.fontFile == nil)

        let file = try TextCommand.parse(base + ["--text", "hi", "--font-file", "/fonts/a.ttf"]).typography.style
        #expect(file.fontFile == URL(fileURLWithPath: "/fonts/a.ttf") && file.font == "sans")
    }

    @Test func textStyleCarriesStrokeShadowAndLayout() throws {
        let command = try TextCommand.parse(base + [
            "--text", "hi", "--color", "10,20,30", "--stroke-width", "2", "--stroke-color", "255,0,0",
            "--shadow-offset-x", "3", "--shadow-offset-y", "4", "--shadow-opacity", "0.25",
            "--text-width", "200", "--text-height", "80", "--rotation", "15",
        ])
        let style = command.typography.style
        #expect(style.stroke == TextStroke(color: Color(red: 1, green: 0, blue: 0), width: 2))
        #expect(style.shadow?.offsetX == 3 && style.shadow?.offsetY == 4)
        #expect(style.shadow?.color.opacity == 0.25)
        #expect(style.rotation == 15)
        #expect(command.typography.layout == .fit(width: 200, height: 80))
    }

    @Test func benchmarkRejectsNegativeCounts() throws {
        _ = try PipelineBenchmarkCommand.parse(["--input", "in.jpg", "--vips-concurrency", "4", "--warmup", "0"])
        rejects(PipelineBenchmarkCommand.self, ["--input", "in.jpg", "--vips-concurrency", "-1"])
        rejects(PipelineBenchmarkCommand.self, ["--input", "in.jpg", "--iterations", "0"])
    }
}

/// Encoder construction: the CLI overrides only what was typed.
@Suite struct EncoderFactoryTests {
    @Test func omittedFlagsKeepEachEncodersLibraryDefaults() {
        let none = EncoderSettings()
        #expect(EncoderFactory.encoder(for: .jpeg, settings: none) == .jpeg(JPEGOptions()))
        #expect(EncoderFactory.encoder(for: .png, settings: none) == .png(PNGOptions()))
        #expect(EncoderFactory.encoder(for: .webp, settings: none) == .webp(WebPOptions()))
        #expect(EncoderFactory.encoder(for: .avif, settings: none) == .avif(AVIFOptions()))
        #expect(EncoderFactory.encoder(for: .heif, settings: none) == .heif(HEIFOptions()))
        #expect(EncoderFactory.encoder(for: .tiff, settings: none) == .tiff(TIFFOptions()))
        #expect(EncoderFactory.encoder(for: .gif, settings: none) == .gif(GIFOptions()))
        #expect(EncoderFactory.encoder(for: .pdf, settings: none) == .pdf(PDFOptions()))
    }

    @Test func suppliedFlagsReachTheTypedOptions() {
        let settings = EncoderSettings(quality: 33, compressionLevel: 9, effort: 2, progressive: true, lossless: true)
        #expect(EncoderFactory.encoder(for: .jpeg, settings: settings) == .jpeg(JPEGOptions(quality: 33, progressive: true)))
        #expect(EncoderFactory.encoder(for: .png, settings: settings) == .png(PNGOptions(compressionLevel: 9, interlaced: true)))
        #expect(EncoderFactory.encoder(for: .webp, settings: settings) == .webp(WebPOptions(quality: 33, effort: 2, lossless: true)))
        #expect(EncoderFactory.encoder(for: .avif, settings: settings) == .avif(AVIFOptions(quality: 33, effort: 2, lossless: true)))
        #expect(EncoderFactory.encoder(for: .heif, settings: settings) == .heif(HEIFOptions(quality: 33, effort: 2, lossless: true)))
        #expect(EncoderFactory.encoder(for: .tiff, settings: settings) == .tiff(TIFFOptions(quality: 33)))
        #expect(EncoderFactory.encoder(for: .gif, settings: settings) == .gif(GIFOptions(effort: 2, interlaced: true)))
    }

    @Test func everyOutputFormatHasAnEncoderAndSVGHasNone() {
        let formats = Set(OutputFormatArgument.allCases.map(\.format))
        #expect(formats == Set(ImageFormat.allCases).subtracting([.svg]))
    }
}
