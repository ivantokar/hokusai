import Foundation
import ArgumentParser
import Hokusai
import Prompt

struct InfoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Show Hokusai and libvips version information."
    )

    /// PURPOSE: Print runtime versions for Hokusai and libvips.
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

    /// PURPOSE: Show decoded metadata for a local image file.
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


