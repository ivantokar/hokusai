import Foundation
import ArgumentParser
import Hokusai
import Prompt

struct BenchmarkCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "benchmark",
        abstract: "Measure operation performance.",
        subcommands: [BenchmarkPipelineCommand.self]
    )
}
