import ArgumentParser
import Foundation

/// The shape shared by every command: do the work, report it, and present any
/// failure the same way.
///
/// A command implements ``execute(reporter:)`` and nothing else. Failures are
/// translated in one place, so no command formats an error itself.
protocol ReportingCommand: AsyncParsableCommand {
    var diagnostics: DiagnosticsOptions { get }
    /// What to use instead, for a command that `hokusai run` replaces; `nil` for the others.
    static var replacement: String? { get }
    func execute(reporter: any Reporter) async throws
}

extension ReportingCommand {
    static var replacement: String? { nil }

    func run() async throws {
        try await run(reporter: TerminalReporter())
    }

    /// Runs against any reporter, which is how the commands are tested.
    func run(reporter: any Reporter) async throws {
        if let replacement = Self.replacement {
            FileHandle.standardError.write(Data("warning: `hokusai \(Self.configuration.commandName ?? "")` is deprecated and will be removed in the next major version; use \(replacement)\n".utf8))
        }
        do {
            try await execute(reporter: reporter)
        } catch {
            throw ErrorTranslator.translate(error, verbose: diagnostics.verbose)
        }
    }
}
