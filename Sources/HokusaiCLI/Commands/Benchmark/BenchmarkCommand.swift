import Foundation
import ArgumentParser
import Hokusai
import Prompt

/// Groups benchmark subcommands so their output and options share one namespace.
struct BenchmarkCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "benchmark",
        abstract: "Measure operation performance.",
        subcommands: [BenchmarkPipelineCommand.self]
    )
}
