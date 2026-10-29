import Foundation
import Testing

/// The result of one probe process: its `key=value` report and exit status.
struct ProbeResult {
    var values: [String: String]
    var status: Int32
    var errorOutput: String

    func integer(_ key: String) -> Int? { values[key].flatMap(Int.init) }
    func flag(_ key: String) -> Bool? { values[key].map { $0 == "true" } }
}

enum ProbeError: Error, CustomStringConvertible {
    case notFound(String)
    var description: String {
        switch self { case .notFound(let message): return message }
    }
}

private final class BundleToken {}

/// Finds the probe: `swift test` builds the executable target into the same
/// products directory as the test bundle. `HOKUSAI_PROBE` overrides the search.
func probeURL() throws -> URL {
    let name = "HokusaiProcessProbe"
    if let override = ProcessInfo.processInfo.environment["HOKUSAI_PROBE"] {
        return URL(fileURLWithPath: override)
    }
    // Swift Testing may run through a helper binary, so start from the bundle
    // that holds these tests, then from the binary and the working directory.
    var starts = [Bundle(for: BundleToken.self).bundleURL, Bundle.main.bundleURL]
    if let executable = Bundle.main.executableURL { starts.append(executable) }
    starts.append(URL(fileURLWithPath: CommandLine.arguments[0]))
    let working = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    starts += [working.appendingPathComponent(".build/debug/x"), working.appendingPathComponent(".build/release/x")]

    for start in starts {
        var directory = start.resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<4 {
            let candidate = directory.appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
            directory.deleteLastPathComponent()
        }
    }
    throw ProbeError.notFound("\(name) was not built next to the test bundle; set HOKUSAI_PROBE to its path")
}

/// Runs one scenario in a fresh process. Libvips and the runtime
/// configuration are therefore the process's own, never the test runner's.
func runProbe(_ scenario: String, _ options: [String: String] = [:], environment: [String: String] = [:]) async throws -> ProbeResult {
    let process = Process()
    process.executableURL = try probeURL()
    process.arguments = [scenario] + options.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
    if !environment.isEmpty {
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
    }
    let output = Pipe(), errors = Pipe()
    process.standardOutput = output
    process.standardError = errors
    try process.run()

    // Read before waiting so a full pipe can never stall the child.
    let (standard, diagnostic) = await Task.detached {
        (output.fileHandleForReading.readDataToEndOfFile(), errors.fileHandleForReading.readDataToEndOfFile())
    }.value
    process.waitUntilExit()

    var values: [String: String] = [:]
    for line in String(decoding: standard, as: UTF8.self).split(separator: "\n") {
        guard let separator = line.firstIndex(of: "=") else { continue }
        values[String(line[..<separator])] = String(line[line.index(after: separator)...])
    }
    return ProbeResult(values: values, status: process.terminationStatus, errorOutput: String(decoding: diagnostic, as: UTF8.self))
}
