import ArgumentParser

/// The first-party `hokusai` command.
///
/// Commands are examples of the public Hokusai API: they parse and validate
/// the command line, call public types and operations, and report the result.
/// They add no image processing of their own and never touch the native layer.
public struct HokusaiRootCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "hokusai",
        abstract: "First-party CLI for trying Hokusai image operations and benchmarks.",
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

    public init() {}
}
