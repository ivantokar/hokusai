import ArgumentParser
import Foundation
@testable import HokusaiCommandLine

/// Captures what a command reports so tests can read it back.
final class RecordingReporter: Reporter, @unchecked Sendable {
    private(set) var messages: [String] = []
    private(set) var panels: [String: [(String, String)]] = [:]
    private(set) var tables: [[[String]]] = []

    func header(_ title: String) { messages.append(title) }
    func info(_ message: String) { messages.append(message) }
    func success(_ message: String) { messages.append(message) }
    func panel(_ title: String, rows: [(String, String)]) { panels[title] = rows }
    func table(headers: [String], rows: [[String]]) { tables.append(rows) }
    func summary(_ message: String) { messages.append(message) }
    func displayPath(_ path: String) -> String { path }

    func value(_ key: String, in panel: String) -> String? {
        panels[panel]?.first { $0.0 == key }?.1
    }
}

/// A scratch directory removed when the test ends.
struct ScratchDirectory {
    let url: URL

    init() throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hokusai-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func path(_ name: String) -> String { url.appendingPathComponent(name).path }
    func remove() { try? FileManager.default.removeItem(at: url) }
}

/// Parses and runs a command in-process, the way the binary does.
@discardableResult
func run<C: ReportingCommand>(_ type: C.Type, _ arguments: [String]) async throws -> RecordingReporter {
    let reporter = RecordingReporter()
    let command = try C.parse(arguments)
    try await command.run(reporter: reporter)
    return reporter
}

/// The message a failed command presents, whichever layer rejected it.
func failureMessage<C: ReportingCommand>(of type: C.Type, _ arguments: [String]) async -> String? {
    do {
        _ = try await run(type, arguments)
        return nil
    } catch let error as CommandFailure {
        return error.message
    } catch {
        return C.message(for: error)
    }
}
