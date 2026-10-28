import ArgumentParser

/// The shape shared by every command: do the work, report it, and present any
/// failure the same way.
///
/// A command implements ``execute(reporter:)`` and nothing else. Failures are
/// translated in one place, so no command formats an error itself.
protocol ReportingCommand: AsyncParsableCommand {
    var diagnostics: DiagnosticsOptions { get }
    func execute(reporter: any Reporter) async throws
}

extension ReportingCommand {
    func run() async throws {
        try await run(reporter: TerminalReporter())
    }

    /// Runs against any reporter, which is how the commands are tested.
    func run(reporter: any Reporter) async throws {
        do {
            try await execute(reporter: reporter)
        } catch {
            throw ErrorTranslator.translate(error, verbose: diagnostics.verbose)
        }
    }
}
