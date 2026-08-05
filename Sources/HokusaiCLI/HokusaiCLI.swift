import Foundation
import ArgumentParser
import Hokusai
import Prompt

/// PURPOSE: CLI entrypoint exposing operational and benchmark commands.
/// CONSTRAINTS:
/// - Commands use public Hokusai APIs; ordinary CLI operation never shuts down
///   the process-global libvips runtime explicitly.
/// - Keep output human-readable for local operator workflows.
/// AI HINTS:
/// - Prefer additive subcommands over behavior changes in existing commands.
@main
struct HokusaiCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hokusai",
        abstract: "First-party CLI for testing Hokusai image operations and benchmarks.",
        subcommands: [
            InfoCommand.self,
            InspectCommand.self,
            ResizeCommand.self,
            ThumbnailCommand.self,
            ConvertCommand.self,
            RotateCommand.self,
            CropCommand.self,
            TextCommand.self,
            BenchmarkCommand.self,
        ]
    )
}
