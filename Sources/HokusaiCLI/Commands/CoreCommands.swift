import Foundation
import ArgumentParser
import Hokusai
import Prompt

struct InfoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Show runtime versions, capabilities, and settings."
    )

    /// Initializes the runtime and prints what the linked native build supports.
    mutating func run() async throws {
        let prompt = PromptService()
        let capabilities = try Hokusai.capabilities()
        let status = Hokusai.runtimeStatus

        func list(_ formats: Set<ImageFormat>) -> String {
            let names = ImageFormat.allCases.filter(formats.contains).map(\.rawValue)
            return names.isEmpty ? "none" : names.joined(separator: ", ")
        }

        prompt.header("Hokusai CLI")
        prompt.panel("Runtime", items: [
            ("libvips", capabilities.libvipsVersion),
            ("Input formats", list(capabilities.inputFormats)),
            ("Output formats", list(capabilities.outputFormats)),
            ("Text rendering", capabilities.textRendering ? "yes" : "no"),
            ("Max evaluations", "\(status.maxConcurrentEvaluations)"),
            ("libvips threads", status.vipsConcurrency.map(String.init) ?? "unknown"),
        ])
        prompt.summary("Ready")
    }
}

struct InspectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Inspect image metadata."
    )

    @Option(name: .shortAndLong, help: "Input image path.")
    var input: String

    /// Reads a local image's header and displays the source metadata Hokusai reports.
    mutating func run() async throws {
        let prompt = PromptService()
        try Hokusai.initialize()

        let metadata = try await Hokusai(url: URL(fileURLWithPath: input)).metadata()
        let oriented = metadata.orientedSize

        var items: [(String, String)] = [
            ("Format", metadata.format?.rawValue ?? "unknown"),
            ("Width", "\(metadata.width) px"),
            ("Height", "\(metadata.height) px"),
        ]
        if let orientation = metadata.orientation {
            items.append(("Orientation", "\(orientation) (\(oriented.width)×\(oriented.height) when displayed)"))
        }
        items += [
            ("Channels", "\(metadata.pixel.channels)"),
            ("Has Alpha", metadata.pixel.hasAlpha ? "yes" : "no"),
            ("Pixels", "\(metadata.pixel.interpretation), \(metadata.pixel.sampleFormat)"
                + (metadata.pixel.bitsPerSample.map { ", \($0)-bit" } ?? "")),
        ]
        if let density = metadata.density {
            items.append(("Density", String(format: "%.1f × %.1f dpi", density.horizontal, density.vertical)))
        }
        if metadata.pages.count > 1 {
            items.append((metadata.isAnimated ? "Frames" : "Pages", "\(metadata.pages.count)"))
        }
        if let size = metadata.sourceByteSize {
            items.append(("File size", "\(size) bytes"))
        }
        let embedded = [("EXIF", metadata.exif), ("ICC", metadata.iccProfile), ("XMP", metadata.xmp), ("IPTC", metadata.iptc)]
            .compactMap { $0.1 == nil ? nil : $0.0 }
        if !embedded.isEmpty {
            items.append(("Embedded", embedded.joined(separator: ", ")))
        }

        prompt.header("Image Metadata")
        prompt.panel(prompt.path(input), items: items)
    }
}

