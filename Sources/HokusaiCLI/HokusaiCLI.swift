import Foundation
import ArgumentParser
import Hokusai
import Prompt

/// Entry point for the first-party Hokusai command-line tool.
///
/// Commands deliberately use only public Hokusai APIs. The process-global
/// libvips runtime remains active for the command's lifetime, and output is
/// intended for an operator reading it in a terminal.
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
