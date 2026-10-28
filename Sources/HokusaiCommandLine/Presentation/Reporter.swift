import Prompt

/// What a command tells the operator. Commands depend on this, not on the
/// terminal library, so their output can be captured or replaced.
protocol Reporter {
    func header(_ title: String)
    func info(_ message: String)
    func success(_ message: String)
    func panel(_ title: String, rows: [(String, String)])
    func table(headers: [String], rows: [[String]])
    func summary(_ message: String)
    /// A path shaped for display.
    func displayPath(_ path: String) -> String
}

/// The interactive terminal implementation, backed by Prompt.
struct TerminalReporter: Reporter {
    private let prompt = PromptService()

    func header(_ title: String) { prompt.header(title) }
    func info(_ message: String) { prompt.info(message) }
    func success(_ message: String) { prompt.success(message) }
    func panel(_ title: String, rows: [(String, String)]) { prompt.panel(title, items: rows) }
    func table(headers: [String], rows: [[String]]) { prompt.table(headers: headers, rows: rows, style: .rounded) }
    func summary(_ message: String) { prompt.summary(message) }
    func displayPath(_ path: String) -> String { prompt.path(path) }
}
