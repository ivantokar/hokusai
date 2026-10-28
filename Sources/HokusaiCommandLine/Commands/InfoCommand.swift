import ArgumentParser
import Hokusai

struct InfoCommand: ReportingCommand {
    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Show runtime versions, capabilities, and settings."
    )

    @OptionGroup var diagnostics: DiagnosticsOptions

    /// The one command that initializes the runtime on purpose, so a broken
    /// native install fails here with a clear error instead of at first use.
    func execute(reporter: any Reporter) async throws {
        try Hokusai.initialize()
        let rows = CapabilitySummary.rows(capabilities: try Hokusai.capabilities(), status: Hokusai.runtimeStatus)

        reporter.header("Hokusai CLI")
        reporter.panel("Runtime", rows: rows)
        reporter.summary("Ready")
    }
}
