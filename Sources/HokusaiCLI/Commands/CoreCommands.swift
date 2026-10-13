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
            ("Hokusai", Hokusai.version),
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

    /// Decodes a local image and displays the metadata exposed by Hokusai.
    mutating func run() async throws {
        let prompt = PromptService()
        try Hokusai.initialize()

        let image = try Hokusai(url: URL(fileURLWithPath: input))
        let metadata = try image.metadata()

        prompt.header("Image Metadata")
        prompt.panel(prompt.path(input), items: [
            ("Width", "\(metadata.width) px"),
            ("Height", "\(metadata.height) px"),
            ("Channels", "\(metadata.channels)"),
            ("Has Alpha", metadata.hasAlpha ? "yes" : "no"),
            ("Format", metadata.format?.rawValue ?? "unknown"),
        ])
    }
}

