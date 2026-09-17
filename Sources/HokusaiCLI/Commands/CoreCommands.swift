import Foundation
import ArgumentParser
import Hokusai
import Prompt

struct InfoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Show Hokusai and libvips version information."
    )

    /// Initializes the runtime and prints the Hokusai and linked libvips versions.
    mutating func run() async throws {
        let prompt = PromptService()
        try Hokusai.initialize()

        prompt.header("Hokusai CLI")
        prompt.panel("Runtime", items: [
            ("Hokusai", Hokusai.version),
            ("libvips", Hokusai.vipsVersion),
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

